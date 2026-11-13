# frozen_string_literal: true

require_relative "config"

module Albumart
  # Counters and last-seen times for the metrics endpoint. Times are monotonic
  # only: the Pi has no RTC, so its wall clock steps after boot.
  class Stats
    Snapshot = Data.define(
      :uptime_seconds,
      :last_cover_age_seconds,
      :covers_total,
      :mqtt_connected,
      :mqtt_connects_total,
      :mqtt_disconnects_total,
      :weather_age_seconds,
      :weather_fetch_errors_total,
      :snow_age_seconds,
      :snow_fetch_errors_total,
      :current_slide,
    )

    def initialize(clock: Albumart.monotonic_clock)
      @clock = clock
      @mutex = Mutex.new
      @started_at = clock.call
      @last_cover_at = nil
      @covers = 0
      @mqtt_connected = false
      @mqtt_connects = 0
      @mqtt_disconnects = 0
      @weather_fetched_at = nil
      @weather_fetch_errors = 0
      @snow_fetched_at = nil
      @snow_fetch_errors = 0
      @slide = nil
    end

    def cover_received
      @mutex.synchronize do
        @last_cover_at = @clock.call
        @covers += 1
      end
    end

    def mqtt_connected
      @mutex.synchronize do
        @mqtt_connected = true
        @mqtt_connects += 1
      end
    end

    def mqtt_disconnected
      @mutex.synchronize do
        @mqtt_connected = false
        @mqtt_disconnects += 1
      end
    end

    def weather_fetched
      @mutex.synchronize { @weather_fetched_at = @clock.call }
    end

    def weather_fetch_failed
      @mutex.synchronize { @weather_fetch_errors += 1 }
    end

    def snow_fetched
      @mutex.synchronize { @snow_fetched_at = @clock.call }
    end

    def snow_fetch_failed
      @mutex.synchronize { @snow_fetch_errors += 1 }
    end

    def slide_shown(slide)
      @mutex.synchronize { @slide = slide }
    end

    def snapshot
      @mutex.synchronize do
        now = @clock.call
        Snapshot.new(
          uptime_seconds: now - @started_at,
          last_cover_age_seconds: @last_cover_at && now - @last_cover_at,
          covers_total: @covers,
          mqtt_connected: @mqtt_connected,
          mqtt_connects_total: @mqtt_connects,
          mqtt_disconnects_total: @mqtt_disconnects,
          weather_age_seconds: @weather_fetched_at && now - @weather_fetched_at,
          weather_fetch_errors_total: @weather_fetch_errors,
          snow_age_seconds: @snow_fetched_at && now - @snow_fetched_at,
          snow_fetch_errors_total: @snow_fetch_errors,
          current_slide: @slide,
        )
      end
    end
  end
end
