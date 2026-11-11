# frozen_string_literal: true

require_relative "test_helper"
require "albumart/scheduler"

class SchedulerTest < Minitest::Test
  def setup
    @clock = FakeClock.new
    @scheduler = Albumart::Scheduler.new(clock: @clock)
  end

  def slide_at(offset, weather: true)
    @clock.advance(offset - (@clock.now - @start))
    @scheduler.current(weather_available: weather)
  end

  def start_with_cover(text_card: false)
    @start = @clock.now
    @scheduler.cover_arrived(text_card:)
  end

  def test_without_cover_or_weather_shows_only_time
    @start = @clock.now

    assert_equal :time, slide_at(0, weather: false).slide
    assert_equal :time, slide_at(5, weather: false).slide
    assert_equal :time, slide_at(12, weather: false).slide
  end

  def test_without_cover_alternates_weather_and_time_every_five_seconds
    @start = @clock.now

    assert_equal :weather, slide_at(0).slide
    assert_equal :weather, slide_at(4.9).slide
    assert_equal :time, slide_at(5).slide
    assert_equal :weather, slide_at(10).slide
    assert_equal :time, slide_at(15).slide
  end

  def test_new_cover_shows_art_with_bar_for_the_overlay_then_cycles_from_weather
    start_with_cover

    assert_equal Albumart::Scheduler::Slot.new(slide: :art, bar: true, started_at: @start), slide_at(0)
    assert_equal :art, slide_at(9.9).slide
    assert_equal :weather, slide_at(10).slide
    assert_equal :time, slide_at(15).slide
    assert_equal Albumart::Scheduler::Slot.new(slide: :art, bar: false, started_at: @start + 20), slide_at(20)
    assert_equal :weather, slide_at(25).slide
  end

  def test_text_card_keeps_its_bar_in_the_rotation
    start_with_cover(text_card: true)

    assert slide_at(0).bar
    assert_equal Albumart::Scheduler::Slot.new(slide: :art, bar: true, started_at: @start + 20), slide_at(20)
  end

  def test_missing_weather_is_skipped
    start_with_cover

    assert_equal :time, slide_at(10, weather: false).slide
    assert_equal :art, slide_at(15, weather: false).slide
    assert_equal :time, slide_at(20, weather: false).slide
  end

  def test_weather_lost_mid_slot_moves_straight_to_time
    @start = @clock.now

    assert_equal :weather, slide_at(0).slide
    assert_equal Albumart::Scheduler::Slot.new(slide: :time, bar: false, started_at: @start + 2),
                 slide_at(2, weather: false)
  end

  def test_another_cover_restarts_the_cycle
    start_with_cover
    slide_at(12)
    @clock.advance(1)
    @start = @clock.now
    @scheduler.cover_arrived(text_card: false)

    assert_equal :art, slide_at(0).slide
    assert slide_at(0).bar
    assert_equal :weather, slide_at(10).slide
  end

  def test_art_drops_out_after_the_idle_threshold
    start_with_cover

    assert_equal :art, slide_at(Albumart::ART_IDLE_SECONDS - 5, weather: false).slide
    assert_equal :time, slide_at(Albumart::ART_IDLE_SECONDS, weather: false).slide
    assert_equal :time, slide_at(Albumart::ART_IDLE_SECONDS + 5, weather: false).slide
  end

  def test_weather_and_time_keep_rotating_after_the_idle_threshold
    start_with_cover
    slide_at(Albumart::ART_IDLE_SECONDS)

    slides = [5, 10, 15, 20].map { |extra| slide_at(Albumart::ART_IDLE_SECONDS + extra).slide }

    assert_equal %i[time weather], slides.uniq.sort
    refute_equal slides[0], slides[1]
  end

  def test_new_cover_after_idle_brings_art_back
    start_with_cover
    slide_at(Albumart::ART_IDLE_SECONDS + 7)
    @start = @clock.now
    @scheduler.cover_arrived(text_card: false)

    assert_equal :art, slide_at(0).slide
    assert_equal :weather, slide_at(10).slide
    assert_equal :time, slide_at(15).slide
    assert_equal :art, slide_at(20).slide
  end
end
