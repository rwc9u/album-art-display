# frozen_string_literal: true

require "rmagick"

module Albumart
  # Weather icons drawn from primitives without anti-aliasing, so every LED is
  # either fully lit or off.
  module Icons
    SIZE = 28
    SMALL_SIZE = 16
    SUN = "#FFC400"
    MOON = "#E8E0A0"
    CLOUD = "#E6E6E6"
    BACK_CLOUD = "#8C8C8C"
    STORM_CLOUD = "#787878"
    RAIN = "#3C8CFF"
    SNOW = "#FFFFFF"
    FOG = "#A0A0A0"
    BACKGROUND = "#000000"

    def self.image(condition, day:, size: SIZE)
      image = Magick::Image.new(size, size) { |info| info.background_color = BACKGROUND }
      draw = Magick::Draw.new
      draw.stroke_antialias(false)
      draw.text_antialias(false)
      draw.stroke("none")
      # Scaled primitives stay crisp; resampling the 28px image breaks up the sun's rays.
      draw.scale(size.fdiv(SIZE), size.fdiv(SIZE)) unless size == SIZE
      public_send(condition, draw, day)
      draw.draw(image)
      image
    end

    def self.clear(draw, day)
      day ? sun(draw, 14, 14, 6, 11) : moon(draw, 14, 14, 9)
    end

    def self.partly_cloudy(draw, day)
      day ? sun(draw, 10, 10, 5, 9) : moon(draw, 11, 10, 7)
      cloud(draw, 4, 12, CLOUD)
    end

    def self.cloudy(draw, _day)
      cloud(draw, 8, 5, BACK_CLOUD)
      cloud(draw, 2, 12, CLOUD)
    end

    def self.fog(draw, _day)
      cloud(draw, 3, 2, BACK_CLOUD)
      draw.fill(FOG)
      draw.rectangle(2, 17, 22, 18)
      draw.rectangle(6, 21, 26, 22)
      draw.rectangle(2, 25, 22, 26)
    end

    def self.rain(draw, _day)
      cloud(draw, 3, 3, CLOUD)
      draw.stroke(RAIN).stroke_width(2)
      [8, 14, 20].each { |x| draw.line(x, 20, x - 2, 26) }
      draw.stroke("none")
    end

    def self.snow(draw, _day)
      cloud(draw, 3, 3, CLOUD)
      draw.fill(SNOW)
      [[7, 20], [15, 20], [23, 20], [11, 25], [19, 25]].each do |x, y|
        draw.rectangle(x - 1, y - 1, x, y)
      end
    end

    def self.thunderstorm(draw, _day)
      cloud(draw, 3, 2, STORM_CLOUD)
      draw.fill(SUN)
      draw.polygon(16, 13, 9, 21, 13, 21, 10, 27, 19, 18, 15, 18, 18, 13)
    end

    def self.sun(draw, cx, cy, radius, ray_reach)
      draw.fill(SUN)
      disc(draw, cx, cy, radius)
      draw.stroke(SUN).stroke_width(2)
      8.times do |step|
        angle = step * Math::PI / 4
        inner = radius + 2
        draw.line(
          (cx + inner * Math.cos(angle)).round, (cy + inner * Math.sin(angle)).round,
          (cx + ray_reach * Math.cos(angle)).round, (cy + ray_reach * Math.sin(angle)).round,
        )
      end
      draw.stroke("none")
    end

    def self.moon(draw, cx, cy, radius)
      draw.fill(MOON)
      disc(draw, cx, cy, radius)
      draw.fill(BACKGROUND)
      disc(draw, cx + (radius * 0.5).round, cy - (radius * 0.4).round, radius - 1)
    end

    # A cloud roughly 22x14 px with its top-left corner at (x, y).
    def self.cloud(draw, x, y, color)
      draw.fill(color)
      disc(draw, x + 6, y + 8, 5)
      disc(draw, x + 12, y + 6, 6)
      disc(draw, x + 17, y + 9, 4)
      draw.rectangle(x + 2, y + 9, x + 20, y + 13)
    end

    def self.disc(draw, cx, cy, radius)
      draw.circle(cx, cy, cx + radius, cy)
    end
  end
end
