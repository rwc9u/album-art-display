# frozen_string_literal: true

module Albumart
  # Everything the renderer needs for one frame.
  Scene = Data.define(:slide, :art, :title, :artist, :bar, :elapsed, :weather, :clock_face) do
    def animated?
      bar
    end

    # Equal keys mean the panel already shows this scene.
    def key
      case slide
      when :art then [slide, art.object_id, bar]
      when :time then [slide, clock_face]
      when :weather then [slide, weather]
      end
    end
  end
end
