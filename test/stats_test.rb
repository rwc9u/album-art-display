# frozen_string_literal: true

require_relative "test_helper"
require "albumart/stats"

class StatsTest < Minitest::Test
  def setup
    @clock = FakeClock.new
    @stats = Albumart::Stats.new(clock: @clock)
  end

  def test_starts_empty
    expected = Albumart::Stats::Snapshot.new(
      uptime_seconds: 0.0,
      last_cover_age_seconds: nil,
      covers_total: 0,
      mqtt_connected: false,
      mqtt_connects_total: 0,
      mqtt_disconnects_total: 0,
      weather_age_seconds: nil,
      weather_fetch_errors_total: 0,
      snow_age_seconds: nil,
      snow_fetch_errors_total: 0,
      current_slide: nil,
    )

    assert_equal expected, @stats.snapshot
  end

  def test_uptime_follows_the_clock
    @clock.advance(90)

    assert_equal 90.0, @stats.snapshot.uptime_seconds
  end

  def test_counts_covers_and_ages_the_latest
    @stats.cover_received
    @clock.advance(30)
    @stats.cover_received
    @clock.advance(12)

    snapshot = @stats.snapshot

    assert_equal 2, snapshot.covers_total
    assert_equal 12.0, snapshot.last_cover_age_seconds
  end

  def test_tracks_the_mqtt_connection
    @stats.mqtt_connected
    @stats.mqtt_disconnected
    @stats.mqtt_disconnected
    @stats.mqtt_connected

    snapshot = @stats.snapshot

    assert snapshot.mqtt_connected
    assert_equal 2, snapshot.mqtt_connects_total
    assert_equal 2, snapshot.mqtt_disconnects_total
  end

  def test_disconnect_clears_the_connected_flag
    @stats.mqtt_connected
    @stats.mqtt_disconnected

    refute @stats.snapshot.mqtt_connected
  end

  def test_ages_the_last_successful_weather_fetch
    @stats.weather_fetched
    @clock.advance(600)
    @stats.weather_fetch_failed
    @stats.weather_fetch_failed

    snapshot = @stats.snapshot

    assert_equal 600.0, snapshot.weather_age_seconds
    assert_equal 2, snapshot.weather_fetch_errors_total
  end

  def test_failed_fetches_alone_leave_the_weather_age_unknown
    @stats.weather_fetch_failed

    assert_nil @stats.snapshot.weather_age_seconds
  end

  def test_ages_the_last_successful_snow_fetch
    @stats.snow_fetched
    @clock.advance(1800)
    @stats.snow_fetch_failed
    @stats.snow_fetch_failed

    snapshot = @stats.snapshot

    assert_equal 1800.0, snapshot.snow_age_seconds
    assert_equal 2, snapshot.snow_fetch_errors_total
  end

  def test_failed_snow_fetches_alone_leave_the_snow_age_unknown
    @stats.snow_fetch_failed

    assert_nil @stats.snapshot.snow_age_seconds
  end

  def test_records_the_current_slide
    @stats.slide_shown(:weather)
    @stats.slide_shown(:time)

    assert_equal :time, @stats.snapshot.current_slide
  end
end
