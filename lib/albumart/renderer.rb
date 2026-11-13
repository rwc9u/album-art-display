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
    FORECAST_COLUMN = WIDTH / 3.0
    FORECAST_MIN_SIZE = 6
    FORECAST_DAY_SIZE = 9
    FORECAST_TEMP_SIZE = 11
    WIDTH_CACHE_LIMIT = 256
    INK_THRESHOLD = 32

    def initialize
      @font = FONT_CANDIDATES.find { |path| File.exist?(path) }
      @scratch = Magick::Image.new(1, 1)
      @draws = {}
      @metrics = {}
      @ink = {}
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
      when :forecast then forecast_slide(scene.weather)
      when :snow then snow_slide(scene.snow, scene.mountain_weather)
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

    def forecast_slide(reading)
      image = blank
      days = reading.forecast
      day_size = column_size(days.map(&:weekday), FORECAST_DAY_SIZE)
      temp_size = column_size(days.flat_map { |day| [day.high.to_s, day.low.to_s] }, FORECAST_TEMP_SIZE)
      days.each_with_index do |day, column|
        centre = FORECAST_COLUMN * (column + 0.5)
        icon = Icons.image(day.condition, day: true, size: Icons::SMALL_SIZE)
        centered_at(image, day.weekday, day_size, centre, 4, LIGHT_GREY)
        image.composite!(icon, (centre - (Icons::SMALL_SIZE / 2.0)).round, 16, Magick::OverCompositeOp)
        centered_at(image, day.high.to_s, temp_size, centre, 36, HIGH_COLOR)
        centered_at(image, day.low.to_s, temp_size, centre, 49, LOW_COLOR)
      end
      image
    end

    def snow_slide(reading, weather)
      image = blank
      board_y, depth_bottom, open_top = weather ? [0, 31, 54] : [6, 42, 50]
      snow_header(image, board_y)
      base_depth(image, "#{reading.base_depth}\"", depth_bottom)
      mountain_weather_row(image, weather, 36) if weather
      open = "#{reading.percent_open}% OPEN"
      size = fitted_size(open, 10, WIDTH - 6)
      ink_top_at(image, open, size, (WIDTH - text_width(open, size)) / 2.0, open_top, DATE_COLOR)
      image
    end

    def snow_header(image, y)
      board_x = WIDTH - Icons::SMALL_SIZE - 1
      image.composite!(Icons.snowboard_image(size: Icons::SMALL_SIZE), board_x, y, Magick::OverCompositeOp)
      size = fitted_size(SNOW_RESORT_LABEL, 9, board_x - 4)
      ink_top_at(image, SNOW_RESORT_LABEL, size, 2, y + icon_centred(SNOW_RESORT_LABEL, size), LIGHT_GREY)
    end

    def base_depth(image, depth, bottom)
      gap = 3
      caption_width = text_width("BASE", 8)
      size = fitted_size(depth, 18, WIDTH - 4 - gap - caption_width)
      x = (WIDTH - text_width(depth, size) - gap - caption_width) / 2.0
      ink_bottom_at(image, depth, size, x, bottom, WHITE)
      ink_bottom_at(image, "BASE", 8, x + text_width(depth, size) + gap, bottom, GREY)
    end

    def mountain_weather_row(image, weather, y)
      high = weather.high.to_s
      low = weather.low.to_s
      gap = 4
      size = 10.downto(MIN_FIT_SIZE).find do |s|
        Icons::SMALL_SIZE + gap + line_width(high, low, gap, s) <= WIDTH - 4
      end || MIN_FIT_SIZE
      x = ((WIDTH - Icons::SMALL_SIZE - gap - line_width(high, low, gap, size)) / 2.0).round
      icon = Icons.image(weather.condition, day: weather.day, size: Icons::SMALL_SIZE)
      image.composite!(icon, x, y, Magick::OverCompositeOp)
      top = y + icon_centred(high + low, size)
      text_x = x + Icons::SMALL_SIZE + gap
      ink_top_at(image, high, size, text_x, top, HIGH_COLOR, measure: high + low)
      ink_top_at(image, low, size, text_x + text_width(high, size) + gap, top, LOW_COLOR, measure: high + low)
    end

    def icon_centred(text, size)
      ((Icons::SMALL_SIZE - ink_rows(text, size).last) / 2.0).round
    end

    def ink_top_at(image, text, size, x, top, color, measure: text)
      annotate(image, text, size, x, top - ink_rows(measure, size).first, color)
    end

    def ink_bottom_at(image, text, size, x, bottom, color)
      offset, height = ink_rows(text, size)
      annotate(image, text, size, x, bottom - height + 1 - offset, color)
    end

    # ImageMagick 6 (Pi) and 7 place annotate text and report its metrics differently, so measure the ink.
    def ink_rows(text, size)
      @ink.clear if @ink.size > WIDTH_CACHE_LIMIT
      @ink[[text, size]] ||= begin
        margin = size * 2
        width = text_width(text, size).ceil + (margin * 2)
        probe = Magick::Image.new(width, margin * 3) { |info| info.background_color = "#000000" }
        annotate(probe, text, size, margin, margin, WHITE)
        rows = probe.export_pixels_to_str(0, 0, width, margin * 3, "RGB").bytes.each_slice(width * 3).to_a
        probe.destroy!
        inked = rows.each_index.select { |row| rows[row].any? { |value| value > INK_THRESHOLD } }
        inked.empty? ? [0, 0] : [inked.first - margin, inked.last - inked.first + 1]
      end
    end

    # One size per row so the three columns match; may go below MIN_FIT_SIZE for the Pi's wider font.
    def column_size(texts, largest)
      largest.downto(FORECAST_MIN_SIZE).find do |size|
        texts.all? { |text| text_width(text, size) <= FORECAST_COLUMN - 2 }
      end || FORECAST_MIN_SIZE
    end

    def centered_at(image, text, size, centre, y, color)
      annotate(image, text, size, centre - (text_width(text, size) / 2.0), y, color)
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
      type_metrics(text, size).width
    end

    def type_metrics(text, size)
      @metrics.clear if @metrics.size > WIDTH_CACHE_LIMIT
      @metrics[[text, size]] ||= text_draw(size, WHITE).get_type_metrics(@scratch, literal(text))
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
