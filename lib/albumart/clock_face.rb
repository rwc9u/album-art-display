# frozen_string_literal: true

require_relative "config"

module Albumart
  # The text shown on the time slide, from wall-clock time.
  ClockFace = Data.define(:time, :meridiem, :date) do
    def self.at(time, twenty_four_hour: TIME_24H)
      if twenty_four_hour
        new(time: time.strftime("%H:%M"), meridiem: nil, date: time.strftime("%a %b %-d"))
      else
        new(time: time.strftime("%-l:%M"), meridiem: time.strftime("%p"), date: time.strftime("%a %b %-d"))
      end
    end
  end
end
