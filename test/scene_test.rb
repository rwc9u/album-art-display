# frozen_string_literal: true

require_relative "test_helper"
require "albumart/scene"
require "albumart/weather"
require "albumart/snow_report"

class SceneTest < Minitest::Test
  SNOW = Albumart::SnowReport::Reading.new(base_depth: 18, percent_open: 2, reported_at: 0, fetched_at: 0.0)

  def mountain(condition, day: true)
    Albumart::Weather::Reading.new(
      temperature: 20, condition:, day:, high: 25, low: 8, forecast: [], fetched_at: 0.0,
    )
  end

  def snow_scene(snow: SNOW, mountain_weather: nil)
    Albumart::Scene.new(
      slide: :snow, art: nil, title: "", artist: "", bar: false, elapsed: 0.0, weather: nil, clock_face: nil,
      snow:, mountain_weather:,
    )
  end

  def test_snow_key_changes_with_the_reading
    refute_equal snow_scene.key, snow_scene(snow: SNOW.with(base_depth: 19)).key
    refute_equal snow_scene.key, snow_scene(snow: SNOW.with(percent_open: 3)).key
  end

  def test_snow_key_ignores_fetch_times
    assert_equal snow_scene.key, snow_scene(snow: SNOW.with(fetched_at: 60.0)).key
  end

  def test_snow_key_changes_with_the_mountain_weather
    refute_equal snow_scene.key, snow_scene(mountain_weather: mountain(:snow)).key
    refute_equal snow_scene(mountain_weather: mountain(:snow)).key, snow_scene(mountain_weather: mountain(:clear)).key
    refute_equal snow_scene(mountain_weather: mountain(:clear)).key,
                 snow_scene(mountain_weather: mountain(:clear, day: false)).key
  end

  def test_snow_key_changes_with_the_mountain_high_and_low
    refute_equal snow_scene(mountain_weather: mountain(:snow)).key,
                 snow_scene(mountain_weather: mountain(:snow).with(high: 26)).key
    refute_equal snow_scene(mountain_weather: mountain(:snow)).key,
                 snow_scene(mountain_weather: mountain(:snow).with(low: 7)).key
  end

  def test_snow_key_is_stable_without_mountain_weather
    refute_nil snow_scene.key
    assert_equal snow_scene.key, snow_scene.key
  end

  def test_snow_key_ignores_the_mountain_temperature
    assert_equal snow_scene(mountain_weather: mountain(:snow)).key,
                 snow_scene(mountain_weather: mountain(:snow).with(temperature: 30)).key
  end
end
