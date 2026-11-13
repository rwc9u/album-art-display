# frozen_string_literal: true

require_relative "test_helper"
require "net/http"
require "albumart/stats"
require "albumart/metrics_server"

class MetricsServerTest < Minitest::Test
  def setup
    @clock = FakeClock.new
    @stats = Albumart::Stats.new(clock: @clock)
    @server = Albumart::MetricsServer.new(stats: @stats, port: 0, bind: "127.0.0.1")
    @thread = Thread.new { @server.start }
  end

  def teardown
    @server.shutdown
    @thread.join
  end

  def get(path)
    Net::HTTP.get_response(URI("http://127.0.0.1:#{@server.port}#{path}"))
  end

  def test_serves_the_text_format
    response = get("/metrics")

    assert_equal "200", response.code
    assert_equal "text/plain; version=0.0.4; charset=utf-8", response["Content-Type"]
  end

  def test_reports_totals_as_counters_and_state_as_gauges
    @stats.cover_received
    @stats.cover_received
    @stats.mqtt_connected
    @stats.weather_fetched
    @stats.weather_fetch_failed
    @stats.snow_fetched
    @stats.snow_fetch_failed
    @stats.snow_fetch_failed
    @stats.slide_shown(:time)
    @clock.advance(7)

    lines = get("/metrics").body.lines(chomp: true)

    assert_includes lines, "# TYPE albumart_uptime_seconds gauge"
    assert_includes lines, "albumart_uptime_seconds 7.0"
    assert_includes lines, "# TYPE albumart_last_cover_age_seconds gauge"
    assert_includes lines, "albumart_last_cover_age_seconds 7.0"
    assert_includes lines, "# TYPE albumart_covers_total counter"
    assert_includes lines, "albumart_covers_total 2.0"
    assert_includes lines, "# TYPE albumart_mqtt_connected gauge"
    assert_includes lines, "albumart_mqtt_connected 1.0"
    assert_includes lines, "# TYPE albumart_mqtt_connects_total counter"
    assert_includes lines, "albumart_mqtt_connects_total 1.0"
    assert_includes lines, "# TYPE albumart_mqtt_disconnects_total counter"
    assert_includes lines, "albumart_mqtt_disconnects_total 0.0"
    assert_includes lines, "# TYPE albumart_weather_age_seconds gauge"
    assert_includes lines, "albumart_weather_age_seconds 7.0"
    assert_includes lines, "# TYPE albumart_weather_fetch_errors_total counter"
    assert_includes lines, "albumart_weather_fetch_errors_total 1.0"
    assert_includes lines, "# TYPE albumart_snow_age_seconds gauge"
    assert_includes lines, "albumart_snow_age_seconds 7.0"
    assert_includes lines, "# TYPE albumart_snow_fetch_errors_total counter"
    assert_includes lines, "albumart_snow_fetch_errors_total 2.0"
    assert_includes lines, "# TYPE albumart_current_slide gauge"
    assert_includes lines, 'albumart_current_slide{slide="weather"} 0.0'
    assert_includes lines, 'albumart_current_slide{slide="forecast"} 0.0'
    assert_includes lines, 'albumart_current_slide{slide="snow"} 0.0'
    assert_includes lines, 'albumart_current_slide{slide="time"} 1.0'
    assert_includes lines, 'albumart_current_slide{slide="art"} 0.0'
  end

  def test_leaves_out_ages_that_are_not_known_yet
    body = get("/metrics").body

    refute_includes body, "albumart_last_cover_age_seconds"
    refute_includes body, "albumart_weather_age_seconds"
    refute_includes body, "albumart_snow_age_seconds"
    assert_includes body.lines(chomp: true), "albumart_covers_total 0.0"
    assert_includes body.lines(chomp: true), "albumart_mqtt_connected 0.0"
  end

  def test_other_paths_are_not_found
    assert_equal "404", get("/").code
    assert_equal "404", get("/metrics/extra").code
  end

  def test_ignores_a_query_string
    response = get("/metrics?x=1")

    assert_equal "200", response.code
    assert_includes response.body.lines(chomp: true), "albumart_covers_total 0.0"
  end

  def test_a_second_server_on_the_same_port_fails_in_new
    assert_raises(Errno::EADDRINUSE) do
      Albumart::MetricsServer.new(stats: @stats, port: @server.port, bind: "127.0.0.1")
    end
  end

  def test_shutdown_before_start_releases_the_port_and_can_repeat
    idle = Albumart::MetricsServer.new(stats: @stats, port: 0, bind: "127.0.0.1")

    idle.shutdown
    idle.shutdown
    rebound = Albumart::MetricsServer.new(stats: @stats, port: idle.port, bind: "127.0.0.1")
    rebound.shutdown

    assert_equal idle.port, rebound.port
  end
end
