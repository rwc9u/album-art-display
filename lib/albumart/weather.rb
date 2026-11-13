# frozen_string_literal: true

require "date"
require "json"
require "net/http"
require "openssl"
require "uri"
require_relative "config"

module Albumart
  # Current conditions and a 3-day forecast from Open-Meteo (keyless). Location
  # comes only from the environment and must never be logged.
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

    Reading = Data.define(:temperature, :condition, :day, :high, :low, :forecast, :fetched_at)
    ForecastDay = Data.define(:weekday, :condition, :high, :low)
    FORECAST_DAYS = 3

    def self.condition_for(code)
      CONDITION_BY_CODE.fetch(code, :cloudy)
    end

    def self.request_uri(settings)
      query = URI.encode_www_form(
        latitude: settings.latitude,
        longitude: settings.longitude,
        current: "temperature_2m,weather_code,is_day",
        daily: "weather_code,temperature_2m_max,temperature_2m_min",
        temperature_unit: settings.units,
        timezone: "auto",
        forecast_days: FORECAST_DAYS + 1,
      )
      URI("#{ENDPOINT}?#{query}")
    end

    def self.parse(body, fetched_at:)
      response = JSON.parse(body, symbolize_names: true)
      case response
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
          forecast: forecast(response[:daily]),
          fetched_at:,
        )
      else
        raise ResponseError, "unexpected response shape"
      end
    rescue JSON::ParserError
      raise ResponseError, "response is not JSON"
    end

    # Lenient: a malformed forecast drops the forecast, never today's reading.
    def self.forecast(daily)
      case daily
      in { time: Array => dates, weather_code: Array => codes,
           temperature_2m_max: Array => highs, temperature_2m_min: Array => lows }
        days = (1..FORECAST_DAYS).map { |index| forecast_day(dates[index], codes[index], highs[index], lows[index]) }
        days.all? ? days : []
      else
        []
      end
    end

    def self.forecast_day(date, code, high, low)
      return unless date.is_a?(String) && code.is_a?(Integer) && high.is_a?(Numeric) && low.is_a?(Numeric)

      weekday = Date.iso8601(date).strftime("%a").upcase
      ForecastDay.new(weekday:, condition: condition_for(code), high: high.round, low: low.round)
    rescue ArgumentError # Date::Error, or Date's length limit on an absurd string
      nil
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
