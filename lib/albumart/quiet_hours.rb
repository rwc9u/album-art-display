# frozen_string_literal: true

require_relative "config"

module Albumart
  # What the panel shows at a wall-clock time: everything, a dim clock, or nothing.
  module QuietHours
    def self.mode_at(time)
      hour = time.hour
      if hour < DAY_START_HOUR || hour >= NIGHT_START_HOUR
        :off
      elsif hour >= EVENING_START_HOUR
        :dim
      else
        :full
      end
    end
  end
end
