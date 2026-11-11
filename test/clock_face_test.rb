# frozen_string_literal: true

require_relative "test_helper"
require "albumart/clock_face"

class ClockFaceTest < Minitest::Test
  def test_twelve_hour_afternoon
    face = Albumart::ClockFace.at(Time.new(2026, 11, 10, 13, 30), twenty_four_hour: false)

    assert_equal Albumart::ClockFace.new(time: "1:30", meridiem: "PM", date: "Tue Nov 10"), face
  end

  def test_twelve_hour_morning_has_no_leading_zero
    face = Albumart::ClockFace.at(Time.new(2026, 11, 10, 9, 5), twenty_four_hour: false)

    assert_equal "9:05", face.time
    assert_equal "AM", face.meridiem
  end

  def test_twelve_hour_midnight_and_noon
    assert_equal "12:05", Albumart::ClockFace.at(Time.new(2026, 11, 10, 0, 5), twenty_four_hour: false).time
    assert_equal "AM", Albumart::ClockFace.at(Time.new(2026, 11, 10, 0, 5), twenty_four_hour: false).meridiem
    assert_equal "PM", Albumart::ClockFace.at(Time.new(2026, 11, 10, 12, 0), twenty_four_hour: false).meridiem
  end

  def test_twenty_four_hour
    face = Albumart::ClockFace.at(Time.new(2026, 11, 1, 21, 5), twenty_four_hour: true)

    assert_equal Albumart::ClockFace.new(time: "21:05", meridiem: nil, date: "Sun Nov 1"), face
  end

  def test_twenty_four_hour_just_after_midnight
    assert_equal "00:05", Albumart::ClockFace.at(Time.new(2026, 11, 10, 0, 5), twenty_four_hour: true).time
  end

  def test_defaults_to_twelve_hour
    assert_equal "PM", Albumart::ClockFace.at(Time.new(2026, 11, 10, 13, 30)).meridiem
  end
end
