##
# This file is part of WhatWeb and may be subject to
# redistribution and commercial restrictions. Please see the WhatWeb
# web site for more information on licensing and terms of use.
# https://morningstarsecurity.com/research/whatweb
##
require 'minitest/autorun'
require 'tmpdir'
require './lib/whatweb'
require './lib/messages'
require './lib/simple_cookie_jar'

class WhatWebTest < Minitest::Test

  def setup
    @test_host = 'whatweb.net'
  end

  #
  # @note test public methods
  #
  def test_public_methods
    assert_equal(true, WhatWeb::Scan.public_method_defined?(:scan))
    assert_equal(true, WhatWeb::Scan.public_method_defined?(:add_target))
    assert_equal(true, WhatWeb::Scan.public_method_defined?(:scan_from_plugin))
  end

  #
  # @note test private methods
  #
  def test_private_methods
    assert_equal(true, WhatWeb::Scan.private_method_defined?(:prepare_target))
    assert_equal(true, WhatWeb::Scan.private_method_defined?(:make_target_list))
  end

  def test_missing_input_file
    err = assert_raises(RuntimeError) do
      WhatWeb::Scan.new([], input_file: '/tmp/whatweb-missing-targets-does-not-exist.txt')
    end
    assert_match(/Input file not found/, err.message)
  end

  def test_input_file_targets
    path = File.join(Dir.tmpdir, "whatweb-targets-#{Process.pid}.txt")
    File.write(path, "# comment\nexample.com\n\n")
    scanner = WhatWeb::Scan.new([], input_file: path)
    assert(scanner)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_invalid_url
    assert_raises 'No targets selected' do
      WhatWeb::Scan.new(nil)
    end
    assert_raises 'No targets selected' do
      WhatWeb::Scan.new('')
    end
    assert_raises 'No targets selected' do
      WhatWeb::Scan.new([])
    end
    assert_raises 'No targets selected' do
      WhatWeb::Scan.new({})
    end
    assert_raises 'No targets selected' do
      WhatWeb::Scan.new([[]])
    end
    assert_raises 'No targets selected' do
      WhatWeb::Scan.new([{}])
    end
  end

  def test_request_headers_do_not_mutate_global_cookie
    previous_headers = $CUSTOM_HEADERS
    previous_jar = defined?($COOKIE_JAR) ? $COOKIE_JAR : nil
    previous_no_cookies = defined?($NO_COOKIES) ? $NO_COOKIES : nil
    $NO_COOKIES = false
    $CUSTOM_HEADERS = { 'Cookie' => 'user=1' }
    $COOKIE_JAR = SimpleCookieJar.new(max_domains: 10)
    $COOKIE_JAR.add_cookies('session=abc', 'https://example.com')

    headers = Target.new('https://example.com/').request_headers
    assert_match(/user=1/, headers['Cookie'])
    assert_match(/session=abc/, headers['Cookie'])
    assert_equal('user=1', $CUSTOM_HEADERS['Cookie'])
  ensure
    $CUSTOM_HEADERS = previous_headers || {}
    $COOKIE_JAR = previous_jar
    $NO_COOKIES = previous_no_cookies
  end

  def test_parse_proxy_ipv6_bracketed
    host, port = Helper.parse_host_port('[::1]:8080', 8080)
    assert_equal('::1', host)
    assert_equal(8080, port)
  end

  def test_parse_proxy_ipv6_bracketed_default_port
    host, port = Helper.parse_host_port('[2001:db8::1]', 8080)
    assert_equal('2001:db8::1', host)
    assert_equal(8080, port)
  end

  def test_parse_proxy_ipv4_host_port
    host, port = Helper.parse_host_port('127.0.0.1:3128', 8080)
    assert_equal('127.0.0.1', host)
    assert_equal(3128, port)
  end

  def test_scanner
    scanner = WhatWeb::Scan.new(@test_host)
    assert(scanner)
  end

  def targets_for(input)
    WhatWeb::Scan.new(input).instance_variable_get(:@targets)
  end

  def test_ipv6_with_port_is_not_dual_scanned
    targets = targets_for('[::1]:8080')
    assert(targets.any? { |u| u.start_with?('http://[::1]:8080') })
    refute(targets.any? { |u| u.start_with?('https://') })
  end

  def test_ipv4_with_port_is_not_dual_scanned
    targets = targets_for('192.168.1.1:8080')
    assert(targets.any? { |u| u.start_with?('http://192.168.1.1:8080') })
    refute(targets.any? { |u| u.start_with?('https://') })
  end

  def test_unbracketed_ipv6_with_path_is_wrapped
    targets = targets_for('2001:db8::1/foo')
    assert(targets.any? { |u| u.include?('[2001:db8::1]') && u.include?('/foo') }, targets.inspect)
  end

  def test_bracketed_ipv6_without_port_is_dual_scanned
    targets = targets_for('[::1]')
    assert(targets.any? { |u| u.start_with?('http://[::1]') })
    assert(targets.any? { |u| u.start_with?('https://[::1]') })
  end

  def test_scan
    max_redirects = 5
    plugins = PluginSupport.load_plugins
    assert(plugins)

    scanner = WhatWeb::Scan.new(@test_host, max_threads: 25)

    scanner.scan do |target|
      assert(target)
      result = WhatWeb::Parser.run_plugins(target, plugins, scanner: scanner)
      assert(result)

      WhatWeb::Redirect.new(target, scanner, max_redirects)

      whatweb_result = WhatWeb::Parser.parse(target, result)
      assert(whatweb_result['target'])
      assert(whatweb_result['status'])
      assert(whatweb_result['result'])
      countries = whatweb_result['result'].select { |a| a[0] == 'Country' }
      assert_equal('Country', countries.first[0])
    end
  end 
end
