# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# The scheduler, weather, snow report, stats and clock code must load without the hardware/image/MQTT/metrics gems.
class PureLoadTest < Minitest::Test
  def test_pure_files_load_without_ffi_rmagick_mqtt_or_metrics_gems
    script = <<~RUBY
      require "albumart/stats"
      require "albumart/scheduler"
      require "albumart/weather"
      require "albumart/snow_report"
      require "albumart/clock_face"
      require "albumart/scene"
      require "albumart/display"
      loaded = %i[FFI Magick MQTT WEBrick Prometheus].select { |name| Object.const_defined?(name) }
      abort "loaded: \#{loaded.join(', ')}" unless loaded.empty?
    RUBY
    lib = File.expand_path("../lib", __dir__)

    output, status = Open3.capture2e(RbConfig.ruby, "-w", "-I", lib, "-e", script)

    assert status.success?, output
    assert_empty output
  end
end
