# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"
require_relative "config"

module Albumart
  # Current conditions from Open-Meteo (keyless). Location comes only from the
  # environment and must never be logged.
  module Weather
    ENDPOINT = "https://api.open-meteo.com/v1/forecast"
    UNITS = %w[fahrenheit celsius].freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    CONDITION_BY_CODE = {
      clear: [0, 1],
      partly_cloudy: [2],
      cloudy: [3],
      fog: [45, 48],
      rain: [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82],
      snow: [71, 73, 75, 77, 85, 86],
      thunderstorm: [95, 96, 99],
    }.flat_map { |condition, codes| codes.map { |code| [code, condition] } }.to_h.freeze

    ConfigError = Class.new(StandardError)
    ResponseError = Class.new(StandardError)

    Settings = Data.define(:latitude, :longitude, :units) do
      def self.from_env(env)
        latitude = env["WEATHER_LAT"].to_s.strip
        longitude = env["WEATHER_LON"].to_s.strip
        units = env.fetch("WEATHER_UNITS", "fahrenheit").strip
        raise ConfigError, "WEATHER_LAT/WEATHER_LON not set" if latitude.empty? || longitude.empty?
        raise ConfigError, "WEATHER_LAT/WEATHER_LON must be numbers" unless numeric?(latitude) && numeric?(longitude)
        raise ConfigError, "WEATHER_UNITS must be one of #{UNITS.join(', ')}" unless UNITS.include?(units)

        new(latitude: Float(latitude), longitude: Float(longitude), units:)
      end

      def self.numeric?(value)
        !Float(value, exception: false).nil?
      end
    end

    Reading = Data.define(:temperature, :condition, :day, :high, :low, :fetched_at)

    def self.condition_for(code)
      CONDITION_BY_CODE.fetch(code, :cloudy)
    end

    def self.request_uri(settings)
      query = URI.encode_www_form(
        latitude: settings.latitude,
        longitude: settings.longitude,
        current: "temperature_2m,weather_code,is_day",
        daily: "temperature_2m_max,temperature_2m_min",
        temperature_unit: settings.units,
        timezone: "auto",
        forecast_days: 1,
      )
      URI("#{ENDPOINT}?#{query}")
    end

    def self.parse(body, fetched_at:)
      case JSON.parse(body, symbolize_names: true)
      in {
        current: { temperature_2m: Numeric => temperature, weather_code: Integer => code, is_day: 0 | 1 => is_day },
        daily: { temperature_2m_max: [Numeric => high, *], temperature_2m_min: [Numeric => low, *] },
      }
        Reading.new(
          temperature: temperature.round,
          condition: condition_for(code),
          day: is_day == 1,
          high: high.round,
          low: low.round,
          fetched_at:,
        )
      else
        raise ResponseError, "unexpected response shape"
      end
    rescue JSON::ParserError
      raise ResponseError, "response is not JSON"
    end

    def self.http_get(uri)
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT,
      ) { |http| http.get(uri.request_uri) }
      raise ResponseError, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    # Refreshes on its own thread; the render thread only reads #current.
    class Fetcher
      FAILURES = [
        ResponseError,
        SystemCallError,
        IOError,
        SocketError,
        Timeout::Error,
        OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse,
      ].freeze

      def initialize(settings:, clock: Albumart.monotonic_clock, http: Weather.method(:http_get), stats: nil)
        @uri = Weather.request_uri(settings)
        @clock = clock
        @http = http
        @stats = stats
        @reading = nil
        @mutex = Mutex.new
      end

      def run
        loop do
          sleep(refresh ? WEATHER_REFRESH_SECONDS : WEATHER_RETRY_SECONDS)
        end
      end

      def refresh
        reading = Weather.parse(@http.call(@uri), fetched_at: @clock.call)
        @mutex.synchronize { @reading = reading }
        @stats&.weather_fetched
        true
      rescue *FAILURES => e
        Albumart.log("[weather] fetch failed: #{e.class}: #{e.message}")
        @stats&.weather_fetch_failed
        false
      end

      def current
        reading = @mutex.synchronize { @reading }
        return if reading.nil? || @clock.call - reading.fetched_at > WEATHER_MAX_AGE_SECONDS

        reading
      end
    end
  end
end
