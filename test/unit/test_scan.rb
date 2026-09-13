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
