# frozen_string_literal: true

require_relative "test_helper"
require "albumart/display"
require "albumart/scheduler"
require "albumart/weather"
require "albumart/snow_report"

class DisplayTest < Minitest::Test
  REPORTS = '[{"base_depth":18,"unit_of_measurement":"in","updated":1794570980}]'
  TRAILS = '[{"status":"open","season":"winter","type":"alpine_trail","include":true}]'
  MOUNTAIN_WEATHER = <<~JSON
    {"current":{"temperature_2m":21.4,"weather_code":73,"is_day":1},
     "daily":{"temperature_2m_max":[25.0],"temperature_2m_min":[8.0]}}
  JSON
  MOUNTAIN = Albumart::Weather::Settings.new(latitude: 39.5, longitude: -106.15, units: "fahrenheit")
  MIDDAY = Time.new(2026, 11, 10, 12, 0, 0, "-07:00")
  EVENING = Time.new(2026, 11, 10, 20, 15, 0, "-07:00")
  NIGHT = Time.new(2026, 11, 10, 23, 30, 0, "-07:00")

  def setup
    @clock = FakeClock.new
    @wall_time = MIDDAY
    @scheduler = Albumart::Scheduler.new(clock: @clock)
    @snow = Albumart::SnowReport::Fetcher.new(
      clock: @clock,
      now: -> { 1_794_570_980 },
      http: ->(uri) { uri.path.end_with?("trails") ? TRAILS : REPORTS },
    )
    @snow.refresh
    @mountain_weather = Albumart::Weather::Fetcher.new(
      settings: MOUNTAIN, clock: @clock, http: ->(_uri) { MOUNTAIN_WEATHER }, label: "mountain weather",
    )
  end

  def display
    Albumart::Display.new(
      renderer: nil,
      matrix: nil,
      scheduler: @scheduler,
      weather: nil,
      snow: @snow,
      mountain_weather: @mountain_weather,
      clock: @clock,
      wall_clock: -> { @wall_time },
    )
  end

  def test_snow_shows_without_mountain_weather
    scene = display.current_scene

    assert_equal :snow, scene.slide
    assert_equal 18, scene.snow.base_depth
    assert_nil scene.mountain_weather
    refute_nil scene.key
  end

  def test_snow_scene_carries_the_mountain_weather
    @mountain_weather.refresh

    scene = display.current_scene

    assert_equal :snow, scene.slide
    assert_equal :snow, scene.mountain_weather.condition
    assert scene.mountain_weather.day
  end

  def test_without_a_snow_reading_the_snow_slide_is_skipped
    @snow = Albumart::SnowReport::Fetcher.new(clock: @clock, http: ->(_uri) { raise "unused" })
    @mountain_weather.refresh

    assert_equal :time, display.current_scene.slide
  end

  def test_evening_shows_only_a_dimmed_clock
    @wall_time = EVENING

    scene = display.current_scene

    assert_equal :time, scene.slide
    assert scene.dimmed
    assert_equal "8:15", scene.clock_face.time
    assert_equal "PM", scene.clock_face.meridiem
  end

  def test_evening_hides_a_new_cover_and_its_title_bar
    @wall_time = EVENING
    shown = display
    shown.handle_message(Albumart::TITLE_TOPIC, "Song".b)
    @scheduler.cover_arrived(text_card: false)

    scene = shown.current_scene

    assert_equal :time, scene.slide
    refute scene.bar
    assert_nil scene.art
  end

  def test_night_turns_the_panel_off
    @wall_time = NIGHT

    scene = display.current_scene

    assert_equal :off, scene.slide
    refute scene.animated?
    refute_nil scene.key
  end

  def test_daytime_rotation_is_not_dimmed
    refute display.current_scene.dimmed
  end
end
