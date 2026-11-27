# frozen_string_literal: true

require_relative "test_helper"
require "albumart/quiet_hours"

class QuietHoursTest < Minitest::Test
  def mode_at(hour, minute)
    Albumart::QuietHours.mode_at(Time.new(2026, 11, 10, hour, minute, 0, "-07:00"))
  end

  def test_full_rotation_from_eight_until_six
    assert_equal :full, mode_at(8, 0)
    assert_equal :full, mode_at(12, 30)
    assert_equal :full, mode_at(17, 59)
  end

  def test_dimmed_clock_from_six_until_eleven
    assert_equal :dim, mode_at(18, 0)
    assert_equal :dim, mode_at(22, 59)
  end

  def test_off_from_eleven_until_eight
    assert_equal :off, mode_at(23, 0)
    assert_equal :off, mode_at(0, 30)
    assert_equal :off, mode_at(7, 59)
  end
end
