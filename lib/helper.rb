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

#
# Helper methods for output and conversion
#
module Helper

  # converts Hash, Array, or String to UTF-8
  def self.utf8_elements!(obj)
    if obj.class == Hash
      obj.each_value do |x|
        utf8_elements!(x)
      end
    elsif obj.class == Array
      obj.each do |x|
        utf8_elements!(x)
      end
    elsif obj.class == String
      convert_to_utf8(obj)
    end
  end

  # Converts a string to UTF-8
  def self.convert_to_utf8(str)
    begin
      if (str.frozen?)
        str.dup.force_encoding("UTF-8").scrub
      else
        str.force_encoding("UTF-8").scrub
      end
    rescue => e
      raise "Can't convert to UTF-8 #{e}"
    end
  end

  #
  # Takes an integer of certainty (between 1 - 100)
  #
  # returns String a word representing the certainty
  #
  def self.certainty_to_words(certainty)
    case certainty
    when 0..49
      'maybe'
    when 50..99
      'probably'
    when 100
      'certain'
    end
  end

  #
  # Word wraps a string. Used by plugin_info and OutputVerbose.
  #
  # returns Array an array of lines.
  #
  def self.word_wrap(str, width = 10)
    ret = []
    line = ''

    str.to_s.split.each do |word|
      if line.size + word.size + 1 <= width
        line += "#{word} "
        next
      end

      ret << line

      if word.size <= width
        line = "#{word} "
        next
      end

      line = ''
      w = word.clone

      while w.size > width
        ret << w[0..(width - 1)]
        w = w[width.to_i..-1]
      end

      ret << w unless w.empty?
    end

    ret << line unless line.empty?
    ret
  end

  # Parse host[:port] including [IPv6]:port. Returns [host, port].
  # Host is stored without brackets. Port is default_port when omitted.
  def self.parse_host_port(arg, default_port)
    s = arg.to_s.strip
    raise "Invalid host:port #{arg.inspect}" if s.empty?

    if s =~ /\A\[([^\]]+)\](?::(\d+))?\z/
      return [Regexp.last_match(1), (Regexp.last_match(2) || default_port).to_i]
    end

    if s.count(':') > 1
      if s =~ /\A(.+):(\d+)\z/
        prefix = Regexp.last_match(1)
        port = Regexp.last_match(2).to_i
        begin
          return [prefix, port] if IPAddr.new(prefix).ipv6?
        rescue StandardError
          nil
        end
      end
      return [s, default_port.to_i]
    end

    host, port = s.split(':', 2)
    [host, port ? port.to_i : default_port.to_i]
  end
end
