# frozen_string_literal: true

require_relative "test_helper"
require "albumart/weather"
require "albumart/stats"

class WeatherTest < Minitest::Test
  # Trimmed from a real response for a public Berlin coordinate.
  RESPONSE = <<~JSON
    {"latitude":52.512604,"longitude":13.419517,"timezone":"Europe/Berlin",
     "current_units":{"temperature_2m":"°F","weather_code":"wmo code","is_day":""},
     "current":{"time":"2026-11-13T17:30","interval":900,"temperature_2m":44.9,"weather_code":80,"is_day":0},
     "daily_units":{"weather_code":"wmo code","temperature_2m_max":"°F","temperature_2m_min":"°F"},
     "daily":{"time":["2026-11-13","2026-11-14","2026-11-15","2026-11-16"],"weather_code":[80,3,61,80],
              "temperature_2m_max":[47.1,48.0,45.8,52.5],"temperature_2m_min":[37.5,37.4,34.0,40.0]}}
  JSON

  FORECAST = [
    Albumart::Weather::ForecastDay.new(weekday: "SAT", condition: :cloudy, high: 48, low: 37),
    Albumart::Weather::ForecastDay.new(weekday: "SUN", condition: :rain, high: 46, low: 34),
    Albumart::Weather::ForecastDay.new(weekday: "MON", condition: :rain, high: 53, low: 40),
  ].freeze

  SETTINGS = Albumart::Weather::Settings.new(latitude: 52.52, longitude: 13.41, units: "fahrenheit")

  def test_parses_current_conditions_and_todays_range
    reading = Albumart::Weather.parse(RESPONSE, fetched_at: 5.0)

    expected = Albumart::Weather::Reading.new(
      temperature: 45, condition: :rain, day: false, high: 47, low: 38, forecast: FORECAST, fetched_at: 5.0,
    )
    assert_equal expected, reading
  end

  def test_parses_the_next_three_days_as_the_forecast
    reading = Albumart::Weather.parse(RESPONSE, fetched_at: 0.0)

    assert_equal FORECAST, reading.forecast
  end

  def test_a_single_day_response_parses_today_without_a_forecast
    body = RESPONSE.sub('["2026-11-13","2026-11-14","2026-11-15","2026-11-16"]', '["2026-11-13"]')
                   .sub("[80,3,61,80]", "[80]")
                   .sub("[47.1,48.0,45.8,52.5]", "[47.1]")
                   .sub("[37.5,37.4,34.0,40.0]", "[37.5]")

    reading = Albumart::Weather.parse(body, fetched_at: 0.0)

    assert_equal 47, reading.high
    assert_equal [], reading.forecast
  end

  def test_a_null_in_a_forecast_day_drops_the_forecast_but_keeps_today
    body = RESPONSE.sub("[47.1,48.0,45.8,52.5]", "[47.1,48.0,null,52.5]")

    reading = Albumart::Weather.parse(body, fetched_at: 0.0)

    assert_equal 45, reading.temperature
    assert_equal [], reading.forecast
  end

  def test_missing_daily_weather_codes_drop_the_forecast_but_keep_today
    body = RESPONSE.sub('"weather_code":[80,3,61,80],', "")

    reading = Albumart::Weather.parse(body, fetched_at: 0.0)

    assert_equal 38, reading.low
    assert_equal [], reading.forecast
  end

  def test_an_unparseable_forecast_date_drops_the_forecast
    body = RESPONSE.sub('"2026-11-15"', '"someday"')

    assert_equal [], Albumart::Weather.parse(body, fetched_at: 0.0).forecast
  end

  def test_an_overlong_forecast_date_drops_the_forecast
    body = RESPONSE.sub('"2026-11-15"', %("#{'2' * 200}"))

    assert_equal [], Albumart::Weather.parse(body, fetched_at: 0.0).forecast
  end

  def test_parse_rejects_an_unexpected_shape
    assert_raises(Albumart::Weather::ResponseError) do
      Albumart::Weather.parse('{"error":true,"reason":"bad"}', fetched_at: 0.0)
    end
  end

  def test_parse_rejects_missing_daily_values
    body = RESPONSE.sub("[47.1,", "[null,")

    assert_raises(Albumart::Weather::ResponseError) { Albumart::Weather.parse(body, fetched_at: 0.0) }
  end

  def test_parse_rejects_non_json
    assert_raises(Albumart::Weather::ResponseError) { Albumart::Weather.parse("<html>", fetched_at: 0.0) }
  end

  def test_wmo_codes_map_to_conditions
    assert_equal :clear, Albumart::Weather.condition_for(0)
    assert_equal :clear, Albumart::Weather.condition_for(1)
    assert_equal :partly_cloudy, Albumart::Weather.condition_for(2)
    assert_equal :cloudy, Albumart::Weather.condition_for(3)
    assert_equal :fog, Albumart::Weather.condition_for(45)
    assert_equal :rain, Albumart::Weather.condition_for(53)
    assert_equal :rain, Albumart::Weather.condition_for(66)
    assert_equal :rain, Albumart::Weather.condition_for(81)
    assert_equal :snow, Albumart::Weather.condition_for(73)
    assert_equal :snow, Albumart::Weather.condition_for(86)
    assert_equal :thunderstorm, Albumart::Weather.condition_for(95)
    assert_equal :thunderstorm, Albumart::Weather.condition_for(99)
  end

  def test_unknown_wmo_code_falls_back_to_cloudy
    assert_equal :cloudy, Albumart::Weather.condition_for(42)
  end

  def test_settings_default_to_fahrenheit
    settings = Albumart::Weather::Settings.from_env("WEATHER_LAT" => "52.52", "WEATHER_LON" => "13.41")

    assert_equal SETTINGS, settings
  end

  def test_settings_accept_celsius
    env = { "WEATHER_LAT" => "52.52", "WEATHER_LON" => "13.41", "WEATHER_UNITS" => "celsius" }

    assert_equal "celsius", Albumart::Weather::Settings.from_env(env).units
  end

  def test_settings_require_a_location
    error = assert_raises(Albumart::Weather::ConfigError) { Albumart::Weather::Settings.from_env({}) }

    assert_equal "WEATHER_LAT/WEATHER_LON not set", error.message
  end

  def test_settings_reject_a_non_numeric_location
    assert_raises(Albumart::Weather::ConfigError) do
      Albumart::Weather::Settings.from_env("WEATHER_LAT" => "north", "WEATHER_LON" => "13.41")
    end
  end

  def test_settings_reject_unknown_units
    env = { "WEATHER_LAT" => "52.52", "WEATHER_LON" => "13.41", "WEATHER_UNITS" => "kelvin" }

    assert_raises(Albumart::Weather::ConfigError) { Albumart::Weather::Settings.from_env(env) }
  end

  def test_request_asks_for_the_configured_unit
    uri = Albumart::Weather.request_uri(SETTINGS.with(units: "celsius"))
    query = URI.decode_www_form(uri.query).to_h

    assert_equal "api.open-meteo.com", uri.host
    assert_equal "celsius", query["temperature_unit"]
    assert_equal "temperature_2m,weather_code,is_day", query["current"]
    assert_equal "weather_code,temperature_2m_max,temperature_2m_min", query["daily"]
    assert_equal "4", query["forecast_days"]
  end

  def test_fetcher_has_nothing_before_the_first_fetch
    fetcher = Albumart::Weather::Fetcher.new(settings: SETTINGS, clock: FakeClock.new, http: ->(_uri) { RESPONSE })

    assert_nil fetcher.current
  end

  def test_fetcher_stores_a_successful_reading
    clock = FakeClock.new
    requested = []
    fetcher = Albumart::Weather::Fetcher.new(
      settings: SETTINGS, clock:, http: ->(uri) { requested << uri; RESPONSE },
    )

    assert fetcher.refresh
    assert_equal 45, fetcher.current.temperature
    assert_equal [Albumart::Weather.request_uri(SETTINGS)], requested
  end

  def test_fetcher_keeps_the_last_good_reading_when_a_fetch_fails
    responses = [RESPONSE, nil]
    http = ->(_uri) { responses.shift || raise(Albumart::Weather::ResponseError, "HTTP 503") }
    fetcher = Albumart::Weather::Fetcher.new(settings: SETTINGS, clock: FakeClock.new, http:)
    fetcher.refresh

    assert_output("[weather] fetch failed: Albumart::Weather::ResponseError: HTTP 503\n") do
      refute fetcher.refresh
    end
    assert_equal 45, fetcher.current.temperature
  end

  def test_fetcher_names_itself_in_the_failure_log
    http = ->(_uri) { raise Albumart::Weather::ResponseError, "HTTP 503" }
    fetcher = Albumart::Weather::Fetcher.new(settings: SETTINGS, clock: FakeClock.new, http:, label: "mountain weather")

    assert_output("[mountain weather] fetch failed: Albumart::Weather::ResponseError: HTTP 503\n") do
      refute fetcher.refresh
    end
  end

  def test_fetcher_treats_old_data_as_missing
    clock = FakeClock.new
    fetcher = Albumart::Weather::Fetcher.new(settings: SETTINGS, clock:, http: ->(_uri) { RESPONSE })
    fetcher.refresh

    clock.advance(Albumart::WEATHER_MAX_AGE_SECONDS)
    refute_nil fetcher.current
    clock.advance(1)
    assert_nil fetcher.current
  end

  def test_fetcher_records_successes_and_failures_in_stats
    clock = FakeClock.new
    stats = Albumart::Stats.new(clock:)
    responses = [RESPONSE, nil]
    http = ->(_uri) { responses.shift || raise(Albumart::Weather::ResponseError, "HTTP 503") }
    fetcher = Albumart::Weather::Fetcher.new(settings: SETTINGS, clock:, http:, stats:)
    fetcher.refresh
    clock.advance(60)

    assert_output("[weather] fetch failed: Albumart::Weather::ResponseError: HTTP 503\n") { fetcher.refresh }
    assert_equal 60.0, stats.snapshot.weather_age_seconds
    assert_equal 1, stats.snapshot.weather_fetch_errors_total
  end
end
