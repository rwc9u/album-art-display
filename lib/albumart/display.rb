# frozen_string_literal: true

require_relative "config"
require_relative "clock_face"
require_relative "scene"

module Albumart
  # Shared track state plus the render loop. MQTT callbacks arrive on another
  # thread, so all state is read and written under one mutex.
  class Display
    IDLE_TICK = 0.1
    EMPTY_COVER_BYTES = 100

    def initialize(renderer:, matrix:, scheduler:, weather:, clock: Albumart.monotonic_clock)
      @renderer = renderer
      @matrix = matrix
      @scheduler = scheduler
      @weather = weather
      @clock = clock
      @mutex = Mutex.new
      @art = nil
      @title = ""
      @artist = ""
    end

    def handle_message(topic, payload)
      case topic
      when COVER_TOPIC then cover_received(payload)
      when TITLE_TOPIC then @mutex.synchronize { @title = utf8(payload) }
      when ARTIST_TOPIC then @mutex.synchronize { @artist = utf8(payload) }
      end
    end

    def run
      shown_key = nil
      loop do
        scene = current_scene
        if scene.animated? || scene.key != shown_key
          @matrix.show(@renderer.frame(scene))
          shown_key = scene.key
        end
        sleep(scene.animated? ? 1.0 / FPS : IDLE_TICK)
      end
    end

    def current_scene
      reading = @weather&.current
      @mutex.synchronize do
        slot = @scheduler.current(
          weather_available: !reading.nil?,
          forecast_available: !reading.nil? && !reading.forecast.empty?,
        )
        Scene.new(
          slide: slot.slide,
          art: @art,
          title: @title,
          artist: @artist,
          bar: slot.bar && !(@title.empty? && @artist.empty?),
          elapsed: @clock.call - slot.started_at,
          weather: reading,
          clock_face: slot.slide == :time ? ClockFace.at(Time.now) : nil,
        )
      end
    end

    private

    def cover_received(payload)
      if payload.bytesize > EMPTY_COVER_BYTES
        begin
          art = @renderer.decode_cover(payload)
        rescue DecodeError => e
          Albumart.log("[display] decode failed: #{e.message}")
          return
        end
        @mutex.synchronize do
          @art = art
          @scheduler.cover_arrived(text_card: false)
        end
        Albumart.log("[display] new cover (#{payload.bytesize} bytes)")
      else
        # A mid-track join sends no art until the next track, so show the text instead.
        @mutex.synchronize do
          @art = @renderer.blank
          @scheduler.cover_arrived(text_card: true)
        end
      end
    end

    def utf8(payload)
      payload.dup.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
