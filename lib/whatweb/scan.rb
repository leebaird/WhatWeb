# Copyright 2009 to 2025 Andrew Horton and Brendan Coles
#
# This file is part of WhatWeb.
#
# WhatWeb is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# at your option) any later version.
#
# WhatWeb is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with WhatWeb.  If not, see <http://www.gnu.org/licenses/>.

module WhatWeb
  class Scan
    def initialize(urls, input_file: nil, url_prefix: nil, url_suffix: nil, url_pattern: nil, max_threads: 25)
      urls = [urls] if urls.is_a?(String)
      
      # Initialize URL tracking to avoid duplicates
      initialize_url_tracking

      @targets = make_target_list(
        urls,
        input_file: input_file,
        url_prefix: url_prefix,
        url_suffix: url_suffix,
        url_pattern: url_pattern
      )

      error('No targets selected') if @targets.empty?

      @max_threads = max_threads.to_i || 25
      @target_queue = Queue.new # workers consume from this
    end

    def scan
      Thread.abort_on_exception = true if $WWDEBUG

      workers = (1..@max_threads).map do
        Thread.new do
          # keep reading in root tasks until a nil is received
          loop do
            target = @target_queue.pop
            Thread.exit unless target

            # keep processing until there are no more redirects or the limit is hit
            # while target
            begin
              target.open
            rescue => e
              error("ERROR Opening: #{target} - #{e}")
              target = nil # break target loop
              next
            end

            yield target
          end
        end
      end

      # initialize target_queue
      @targets.each do |url|
        target = prepare_target(url)
        next unless target
        @target_queue << target
      end

      # exit

      loop do
        # this might miss redirects from final targets

        # more defensive than comparing against max_threads
        alive = workers.count(&:alive?)
        break if alive == @target_queue.num_waiting && @target_queue.empty?

        sleep 0.05
      end

      # Shut down workers, logging, and plugins
      (1..@max_threads).each { @target_queue << nil }
      workers.each(&:join)
    end

    # for use by Plugins
    def scan_from_plugin(target: nil)
      raise 'No target' unless target

      begin
        target.open
      rescue => e
        error("ERROR Opening: #{target} - #{e}")
      end
      target
    end

    def add_target(url, redirect_counter = 0)
      # Normalize the URL for comparison
      normalized_url = normalize_url_for_comparison(url)
      
      # Check if this URL or a very similar one is already in the queue
      if already_queued_or_processed?(normalized_url)
        debug("Skipping duplicate target: #{url} (already queued or similar)")
        return
      end
      
      # TODO: REVIEW: should this use prepare_target?
      target = Target.new(url, redirect_counter)

      unless target
        error("Add Target Failed - #{url}")
        return
      end
      
      # Add the normalized URL to our tracking list
      track_url(normalized_url)
      
      @target_queue << target
    end

    private
    
    # Track URLs that have been processed or queued to avoid duplicates
    def initialize_url_tracking
      # Track normalized URLs that are queued or processed
      @processed_urls = Set.new
    end
    
    # Normalize a URL for comparison to detect similar/duplicate URLs
    # This helps avoid scanning the same content with trivial URL differences
    def normalize_url_for_comparison(url)
      begin
        # Parse the URL
        uri = URI.parse(url.to_s.strip)
        
        # Convert to lowercase
        host = uri.host.to_s.downcase
        path = uri.path.to_s.downcase
        
        # Remove trailing slashes from path
        path = path.gsub(/\/$/, '')
        path = '/' if path.empty?
        
        # Rebuild normalized URL (without query parameters)
        normalized = "#{uri.scheme}://#{host}#{path}"
        
        return normalized
      rescue => e
        # If URL can't be parsed, just return as is
        return url.to_s
      end
    end
    
    # Track a URL as processed or queued
    def track_url(normalized_url)
      @processed_urls ||= Set.new
      @processed_urls << normalized_url
    end
    
    # Check if a normalized URL or a similar one is already being processed
    def already_queued_or_processed?(normalized_url)
      @processed_urls ||= Set.new
      @processed_urls.include?(normalized_url)
    end

    # try to make a new Target object, may return nil
    def prepare_target(url)
      Target.new(url)
    rescue => e
      error("Prepare Target Failed - #{e}")
      nil
    end

    def ipv6_literal?(host)
      IPAddr.new(host.to_s.sub(/\A\[(.*)\]\z/, '\1')).ipv6?
    rescue StandardError
      false
    end

    # Wrap an IPv6 host in brackets so Addressable/URI can parse it.
    # 2001:db8::1/foo → [2001:db8::1]/foo
    # 2001:db8::1:8080 is treated as IPv6:port when the prefix is a valid IPv6 address.
    def bracket_ipv6_target(s)
      return s if s.start_with?('[')

      host, path = s.split('/', 2)
      port = nil
      unless ipv6_literal?(host)
        if host =~ /\A(.+):(\d+)\z/ && ipv6_literal?(Regexp.last_match(1))
          host = Regexp.last_match(1)
          port = Regexp.last_match(2)
        else
          return s
        end
      end

      wrapped = "[#{host}]"
      wrapped += ":#{port}" if port
      path ? "#{wrapped}/#{path}" : wrapped
    end

    #
    # Make Target List
    #
    # Make a list of targets from a list of URLs and/or input file
    #
    def make_target_list(urls, opts = {})
      url_list = []

      # parse URLs
      if urls.is_a?(Array)
        urls.flatten.reject { |u| u.nil? }.map { |u| u.strip }.reject { |u| u.eql?('') }.each do |url|
          url_list << url
        end
      end

      # parse input file
      # read each line as a url, skipping lines that begin with a #
      inputfile = opts[:input_file] || nil
      unless inputfile.nil?
        raise "Input file not found: #{inputfile}" unless File.exist?(inputfile)
        raise "Input file not readable: #{inputfile}" unless File.readable?(inputfile)

        debug("loading input file: #{inputfile}")
        File.foreach(inputfile) do |line|
          line = line.to_s.sub(/\A\uFEFF/, '').strip
          next if line.empty? || line.start_with?('#')

          url_list << line
        end
      end

      return [] if url_list.empty?

      # TODO: refactor this
      ip_range = url_list.map do |x|
        range = nil
        # Parse IP ranges
        if x =~ %r{^[0-9\.\-\/]+$} && x !~ %r{^[\d\.]+$}
          begin
            # CIDR notation
            if x =~ %r{\d+\.\d+\.\d+\.\d+/\d+$}
              range = IPAddr.new(x).to_range.map(&:to_s)
            # x.x.x.x-x
            elsif x =~ %r{^(\d+\.\d+\.\d+\.\d+)-(\d+)$}
              start_ip = IPAddr.new(Regexp.last_match(1), Socket::AF_INET)
              end_ip   = IPAddr.new("#{start_ip.to_s.split('.')[0..2].join('.')}.#{Regexp.last_match(2)}", Socket::AF_INET)
              range = (start_ip..end_ip).map(&:to_s)
            # x.x.x.x-x.x.x.x
            elsif x =~ %r{^(\d+\.\d+\.\d+\.\d+)-(\d+\.\d+\.\d+\.\d+)$}
              start_ip = IPAddr.new(Regexp.last_match(1), Socket::AF_INET)
              end_ip   = IPAddr.new(Regexp.last_match(2), Socket::AF_INET)
              range = (start_ip..end_ip).map(&:to_s)
            end
          rescue => e
            # Something went horribly wrong parsing the target IP range
            raise "Error parsing target IP range: #{e}"
          end
        end
        range
      end.compact.flatten

      # TODO: refactor this. data which matches these regexs should be taken care of above
      url_list = url_list.select { |x| !(x =~ %r{^[0-9\.\-*\/]+$}) || x =~ /^[\d\.]+$/ }
      url_list += ip_range unless ip_range.empty?

      # make urls friendlier, test if it's a file, if test for not assume it's http://
      # http, https, ftp, etc
      push_to_urllist = []
      consecutive_errors = 0
      inputfile_name = opts[:input_file] # Store for error messages
      
      # TODO: refactor this
      parsed = []
      url_list.each do |x|
        if File.exist?(x)
          consecutive_errors = 0
          parsed << x
          next
        end

        x = opts[:url_pattern].gsub('%insert%', x) unless opts[:url_pattern].to_s.eql?('')
        x = "#{opts[:url_prefix]}#{x}#{opts[:url_suffix]}"

        if x !~ %r{^[a-z]+://}
          x = bracket_ipv6_target(x)

          # Dual-scan HTTP+HTTPS only when there is no path and no explicit port.
          has_port = x.match?(/\A\[[^\]]+\]:\d+\z/) || x.match?(/\A[^\[\/:]+:\d+\z/)

          if x !~ %r{/} && !has_port
            original_hostname = x.dup
            push_to_urllist << "https://#{x}"
            x.sub!(/^/, 'http://')
            debug("Simple hostname detected: #{original_hostname}. Testing both HTTP and HTTPS.")
          else
            x.sub!(/^/, 'http://')
          end
        end

        begin
          domain = Addressable::URI.parse(x)
          raise 'Unable to parse invalid target. No hostname.' if domain.host.empty?

          x = domain.normalize.to_s if domain.host !~ %r{^[a-zA-Z0-9\.:/]*$}
          consecutive_errors = 0
          parsed << x
        rescue => e
          consecutive_errors += 1
          error("Unable to parse invalid target #{x}: #{e}")

          if consecutive_errors >= 10
            error("Aborting target processing after #{consecutive_errors} consecutive parsing errors.")
            error("The input appears to contain invalid URLs or non-URL data.")
            error("Please check your input and ensure it contains valid URLs.")
            break
          end
        end
      end
      url_list = parsed

      url_list += push_to_urllist unless push_to_urllist.empty?

      # compact removes nils
      url_list = url_list.flatten.compact # .sort.uniq
    end
  end
end
