# frozen_string_literal: true

module Albumart
  # Everything the renderer needs for one frame.
  Scene = Data.define(
    :slide, :art, :title, :artist, :bar, :elapsed, :weather, :clock_face, :snow, :mountain_weather, :dimmed,
  ) do
    def initialize(dimmed: false, **) = super

    def animated?
      bar
    end

    # Equal keys mean the panel already shows this scene.
    def key
      case slide
      when :art then [slide, art.object_id, bar]
      when :off then [slide]
      when :time then [slide, clock_face, dimmed]
      when :weather then [slide, weather]
      when :forecast then [slide, weather.forecast]
      when :snow
        [
          slide, snow.base_depth, snow.percent_open,
          mountain_weather&.condition, mountain_weather&.day, mountain_weather&.high, mountain_weather&.low,
        ]
      end
    end
  end
end
