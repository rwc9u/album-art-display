# frozen_string_literal: true

require_relative "config"

module Albumart
  # Decides which slide is on the panel. A new cover shows the art with its
  # title/artist bar, then the rotation restarts from weather.
  class Scheduler
    SLIDES = %i[weather forecast time art].freeze

    Slot = Data.define(:slide, :bar, :started_at)

    def initialize(clock:)
      @clock = clock
      @cover_at = nil
      @text_card = false
      @rotation_from = clock.call
      @index = nil
      @slot_started_at = nil
    end

    def cover_arrived(text_card:)
      @cover_at = @clock.call
      @text_card = text_card
      @rotation_from = @cover_at + OVERLAY_SECONDS
      @index = nil
    end

    def current(weather_available:, forecast_available:)
      now = @clock.call
      return Slot.new(slide: :art, bar: true, started_at: @cover_at) if overlay?(now)

      available = SLIDES.select { |slide| available?(slide, now, weather_available, forecast_available) }
      advance(now, available)
      slide = SLIDES[@index]
      Slot.new(slide:, bar: slide == :art && @text_card, started_at: @slot_started_at)
    end

    private

    def overlay?(now)
      !@cover_at.nil? && now < @cover_at + OVERLAY_SECONDS
    end

    def available?(slide, now, weather_available, forecast_available)
      case slide
      when :weather then weather_available
      when :forecast then forecast_available
      when :time then true
      when :art then !@cover_at.nil? && now - @cover_at < ART_IDLE_SECONDS
      end
    end

    def advance(now, available)
      if @index.nil?
        @index = next_available(0, available)
        @slot_started_at = @rotation_from
      end
      while now - @slot_started_at >= SLIDE_SECONDS
        @slot_started_at += SLIDE_SECONDS
        @index = next_available(@index + 1, available)
      end
      return if available.include?(SLIDES[@index])

      @index = next_available(@index + 1, available)
      @slot_started_at = now
    end

    def next_available(from, available)
      SLIDES.size.times
            .map { |step| (from + step) % SLIDES.size }
            .find { |index| available.include?(SLIDES[index]) }
    end
  end
end
