# frozen_string_literal: true

module Albumart
  BROKER = "localhost"
  PORT = 1883
  TOPIC_PREFIX = "shairport-sync/rpih1"
  COVER_TOPIC = "#{TOPIC_PREFIX}/cover"
  ARTIST_TOPIC = "#{TOPIC_PREFIX}/artist"
  TITLE_TOPIC = "#{TOPIC_PREFIX}/title"

  WIDTH = 64
  HEIGHT = 64

  OVERLAY_SECONDS = 10        # how long the title/artist bar stays after a track change
  SLIDE_SECONDS = 5           # each slide's turn in the weather -> forecast -> time -> art rotation
  ART_IDLE_SECONDS = 60 * 60  # art leaves the rotation after this long with no new cover
  SCROLL_SPEED = 16.0         # pixels/second for text too wide to fit
  SCROLL_START_DELAY = 1.0    # seconds to hold the start of a line before scrolling
  SCROLL_GAP = 12             # pixels of gap between the end and the wrapped start
  FPS = 30                    # animation frame rate while the title/artist bar is showing
  FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
  TIME_24H = false

  WEATHER_REFRESH_SECONDS = 10 * 60
  WEATHER_RETRY_SECONDS = 60
  WEATHER_MAX_AGE_SECONDS = 60 * 60

  DEFAULT_MATRIX_LIB = "/home/rob/rpi-rgb-led-matrix/lib/librgbmatrix.so.1"
  # Fewer PWM bits and a shorter LSB pulse raise the refresh rate so cameras don't
  # catch dark banding; dithering wins back some colour depth.
  MATRIX_OPTIONS = {
    hardware_mapping: "adafruit-hat",
    rows: 64,
    cols: 64,
    chain_length: 1,
    parallel: 1,
    pwm_bits: 8,
    pwm_lsb_nanoseconds: 80,
    pwm_dither_bits: 1,
  }.freeze
  GPIO_SLOWDOWN = 4

  def self.log(message)
    $stdout.puts(message)
  end

  def self.monotonic_clock
    -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
  end
end
