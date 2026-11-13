# frozen_string_literal: true

require "json"
require "uri"
require_relative "config"
require_relative "weather"

module Albumart
  # Copper Mountain's base depth and share of trails open, from undocumented keyless feeds.
  module SnowReport
    ResponseError = Class.new(StandardError)

    Reading = Data.define(:base_depth, :percent_open, :reported_at, :fetched_at)

    SEASONS = %w[winter all].freeze

    # All-or-nothing: either feed in an unexpected shape rejects the whole reading.
    def self.parse(reports_body, trails_body, fetched_at:)
      case JSON.parse(reports_body, symbolize_names: true)
      in [{ base_depth: Numeric => base_depth, unit_of_measurement: "in", updated: Integer => reported_at }, *]
        Reading.new(
          base_depth: base_depth.round,
          percent_open: percent_open(JSON.parse(trails_body, symbolize_names: true)),
          reported_at:,
          fetched_at:,
        )
      else
        raise ResponseError, "unexpected snow report shape"
      end
    rescue JSON::ParserError
      raise ResponseError, "response is not JSON"
    end

    def self.percent_open(trails)
      raise ResponseError, "unexpected trails shape" unless trails.is_a?(Array) && trails.all?(Hash)

      eligible = trails.select { |trail| eligible?(trail) }
      raise ResponseError, "no winter alpine trails" if eligible.empty?

      open = eligible.count { |trail| trail[:status] == "open" }
      percent = (open * 100.0 / eligible.size).round
      open.positive? && percent.zero? ? 1 : percent
    end

    def self.eligible?(trail)
      trail[:type] == "alpine_trail" && trail[:include] == true && SEASONS.include?(trail[:season])
    end

    # Refreshes on its own thread; the render thread only reads #current.
    class Fetcher
      def initialize(
        clock: Albumart.monotonic_clock,
        now: -> { Time.now.to_i },
        http: Weather.method(:http_get),
        stats: nil
      )
        @reports_uri = URI(SNOW_REPORTS_URL)
        @trails_uri = URI(SNOW_TRAILS_URL)
        @clock = clock
        @now = now
        @http = http
        @stats = stats
        @reading = nil
        @mutex = Mutex.new
      end

      def run
        loop do
          sleep(refresh ? SNOW_REFRESH_SECONDS : SNOW_RETRY_SECONDS)
        end
      end

      # Rescues everything: the feed is undocumented and an exception here would exit the process.
      def refresh
        reading = SnowReport.parse(@http.call(@reports_uri), @http.call(@trails_uri), fetched_at: @clock.call)
        @mutex.synchronize { @reading = reading }
        @stats&.snow_fetched
        true
      rescue StandardError => e
        Albumart.log("[snow] fetch failed: #{e.class}: #{e.message}")
        @stats&.snow_fetch_failed
        false
      end

      def current
        reading = @mutex.synchronize { @reading }
        return if reading.nil? || @clock.call - reading.fetched_at > SNOW_MAX_AGE_SECONDS
        # A negative age (the Pi's clock running behind) counts as fresh.
        return if @now.call - reading.reported_at > SNOW_REPORT_STALE_SECONDS

        reading
      end
    end
  end
end
