# frozen_string_literal: true

require "rmagick"
require_relative "config"
require_relative "icons"

module Albumart
  DecodeError = Class.new(StandardError)

  # Turns a Scene into a 64x64 RGB frame with RMagick.
  class Renderer
    FONT_CANDIDATES = [FONT_PATH, "/System/Library/Fonts/Supplemental/Arial Narrow Bold.ttf"].freeze
    # rmagick < 7.1 runs annotate/metrics text through InterpretImageProperties,
    # which expands %-escapes and backslashes and reads a file named by a leading @.
    INTERPRETS_TEXT = Gem::Version.new(Magick::Version[/\d+(\.\d+)+/]) < Gem::Version.new("7.1.0")

    BAR_HEIGHT = 18
    BAR_OPACITY = 170 / 255.0
    TITLE_SIZE = 8
    ARTIST_SIZE = 7
    WHITE = "#FFFFFF"
    LIGHT_GREY = "#D2D2D2"
    GREY = "#9A9A9A"
    DATE_COLOR = "#78B4FF"
    HIGH_COLOR = "#FF9A3C"
    LOW_COLOR = "#78B4FF"
    MIN_FIT_SIZE = 8
    WIDTH_CACHE_LIMIT = 256

    def initialize
      @font = FONT_CANDIDATES.find { |path| File.exist?(path) }
      @scratch = Magick::Image.new(1, 1)
      @draws = {}
      @widths = {}
      @barred = nil
    end

    attr_reader :font

    def decode_cover(blob)
      format = cover_format(blob) or raise DecodeError, "not a JPEG or PNG"
      original = Magick::Image.from_blob(blob) { |info| info.format = format }.first
      original.alpha(Magick::DeactivateAlphaChannel)
      original.colorspace = Magick::SRGBColorspace
      original.resize(WIDTH, HEIGHT, Magick::LanczosFilter).tap { original.destroy! }
    rescue Magick::ImageMagickError => e
      raise DecodeError, e.message
    end

    def blank
      Magick::Image.new(WIDTH, HEIGHT) { |info| info.background_color = "#000000" }
    end

    # Loads the font and type configuration while the process still runs as root.
    def warm_up
      text_width("0", TITLE_SIZE)
    end

    def frame(scene)
      pixels(compose(scene))
    end

    def compose(scene)
      case scene.slide
      when :art then art_slide(scene)
      when :time then time_slide(scene.clock_face)
      when :weather then weather_slide(scene.weather)
      end
    end

    def pixels(image)
      image.export_pixels_to_str(0, 0, WIDTH, HEIGHT, "RGB")
    end

    private

    def cover_format(blob)
      if blob.start_with?("\xFF\xD8\xFF".b)
        "JPEG"
      elsif blob.start_with?("\x89PNG".b)
        "PNG"
      end
    end

    def art_slide(scene)
      return scene.art unless scene.bar

      image = barred(scene.art).copy
      draw_line(image, scene.title, TITLE_SIZE, HEIGHT - BAR_HEIGHT + 1, scene.elapsed, WHITE)
      draw_line(image, scene.artist, ARTIST_SIZE, HEIGHT - 9, scene.elapsed, LIGHT_GREY)
      image
    end

    def barred(art)
      return @barred.last if @barred&.first.equal?(art)

      shade = Magick::Image.new(WIDTH, BAR_HEIGHT) { |info| info.background_color = "rgba(0,0,0,#{BAR_OPACITY})" }
      image = art.composite(shade, 0, HEIGHT - BAR_HEIGHT, Magick::OverCompositeOp)
      @barred = [art, image]
      image
    end

    def draw_line(image, text, size, y, elapsed, color)
      return if text.empty?

      width = text_width(text, size)
      if width <= WIDTH - 2
        annotate(image, text, size, 1, y, color)
        return
      end
      period = width + SCROLL_GAP
      offset = ([elapsed - SCROLL_START_DELAY, 0.0].max * SCROLL_SPEED) % period
      x = 1 - offset
      annotate(image, text, size, x, y, color)
      annotate(image, text, size, x + period, y, color)
    end

    def time_slide(face)
      image = blank
      size = fitted_size(face.time, 22, WIDTH - 2)
      centered(image, face.time, size, face.meridiem ? 6 : 12, WHITE)
      centered(image, face.meridiem, 10, 31, GREY) if face.meridiem
      centered(image, face.date, fitted_size(face.date, 10, WIDTH - 2), face.meridiem ? 46 : 40, DATE_COLOR)
      image
    end

    def weather_slide(reading)
      image = blank
      image.composite!(Icons.image(reading.condition, day: reading.day), 1, 4, Magick::OverCompositeOp)
      temperature = "#{reading.temperature}°"
      size = fitted_size(temperature, 18, WIDTH - 31)
      annotate(image, temperature, size, 30 + ((WIDTH - 31 - text_width(temperature, size)) / 2.0), 10, WHITE)
      high_low(image, "H #{reading.high}", "L #{reading.low}", 44)
      image
    end

    def high_low(image, high, low, y)
      gap = 6
      size = 10.downto(MIN_FIT_SIZE).find { |s| line_width(high, low, gap, s) <= WIDTH - 2 } || MIN_FIT_SIZE
      x = (WIDTH - line_width(high, low, gap, size)) / 2.0
      annotate(image, high, size, x, y, HIGH_COLOR)
      annotate(image, low, size, x + text_width(high, size) + gap, y, LOW_COLOR)
    end

    def line_width(high, low, gap, size)
      text_width(high, size) + gap + text_width(low, size)
    end

    def centered(image, text, size, y, color)
      annotate(image, text, size, (WIDTH - text_width(text, size)) / 2.0, y, color)
    end

    def fitted_size(text, largest, max_width)
      largest.downto(MIN_FIT_SIZE).find { |size| text_width(text, size) <= max_width } || MIN_FIT_SIZE
    end

    def annotate(image, text, size, x, y, color)
      text_draw(size, color).annotate(image, 0, 0, x.round, y, literal(text))
    end

    def text_width(text, size)
      @widths.clear if @widths.size > WIDTH_CACHE_LIMIT
      @widths[[text, size]] ||= text_draw(size, WHITE).get_type_metrics(@scratch, literal(text)).width
    end

    def text_draw(size, color)
      @draws[[size, color]] ||= Magick::Draw.new.tap do |draw|
        draw.font = @font if @font
        draw.pointsize = size
        draw.fill = color
        draw.gravity = Magick::NorthWestGravity
      end
    end

    def literal(text)
      return text unless INTERPRETS_TEXT

      text.gsub(/[%\\]/) { |char| char * 2 }.sub(/\A(\s*)@/) { "#{Regexp.last_match(1)}\\@" }
    end
  end
end
