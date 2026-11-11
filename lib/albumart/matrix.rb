# frozen_string_literal: true

require "ffi"
require_relative "config"

module Albumart
  # The 64x64 panel via hzeller's C API (include/led-matrix-c.h), double-buffered.
  class Matrix
    module Native
      extend FFI::Library

      def self.load(path)
        ffi_lib(path)
        attach_function :led_matrix_create_from_options_and_rt_options, [:pointer, :pointer], :pointer
        attach_function :led_matrix_create_offscreen_canvas, [:pointer], :pointer
        attach_function :led_matrix_swap_on_vsync, [:pointer, :pointer], :pointer, blocking: true
        attach_function :led_canvas_set_pixels, [:pointer, :int, :int, :int, :int, :buffer_in], :void
        attach_function :led_canvas_clear, [:pointer], :void
        attach_function :led_matrix_delete, [:pointer], :void
      end
    end

    # Landmine: fields, types and order must match struct RGBLedMatrixOptions in
    # led-matrix-c.h exactly. Zeroed fields mean "library default".
    class Options < FFI::Struct
      layout :hardware_mapping, :pointer,
             :rows, :int,
             :cols, :int,
             :chain_length, :int,
             :parallel, :int,
             :pwm_bits, :int,
             :pwm_lsb_nanoseconds, :int,
             :pwm_dither_bits, :int,
             :brightness, :int,
             :scan_mode, :int,
             :row_address_type, :int,
             :multiplexing, :int,
             :disable_hardware_pulsing, :bool,
             :show_refresh_rate, :bool,
             :inverse_colors, :bool,
             :led_rgb_sequence, :pointer,
             :pixel_mapper_config, :pointer,
             :panel_type, :pointer,
             :limit_refresh_rate_hz, :int,
             :disable_busy_waiting, :bool
    end

    # Landmine: must match struct RGBLedRuntimeOptions in led-matrix-c.h exactly.
    class RuntimeOptions < FFI::Struct
      layout :gpio_slowdown, :int,
             :rp1_pio, :int,
             :daemon, :int,
             :drop_privileges, :int,
             :do_gpio_init, :bool,
             :drop_priv_user, :pointer,
             :drop_priv_group, :pointer
    end

    FRAME_BYTES = WIDTH * HEIGHT * 3

    def initialize(lib_path:)
      begin
        Native.load(lib_path)
      rescue LoadError => e
        raise LoadError, "cannot load the LED matrix library at #{lib_path} (set RGBMATRIX_LIB): #{e.message}"
      end
      @hardware_mapping = FFI::MemoryPointer.from_string(MATRIX_OPTIONS.fetch(:hardware_mapping))
      @matrix = Native.led_matrix_create_from_options_and_rt_options(options, runtime_options)
      raise "LED matrix initialisation failed (running as root on a Pi?)" if @matrix.null?

      @canvas = Native.led_matrix_create_offscreen_canvas(@matrix)
      @mutex = Mutex.new
    end

    def show(rgb)
      raise ArgumentError, "expected #{FRAME_BYTES} bytes, got #{rgb.bytesize}" unless rgb.bytesize == FRAME_BYTES

      @mutex.synchronize do
        return if @matrix.nil?

        Native.led_canvas_set_pixels(@canvas, 0, 0, WIDTH, HEIGHT, rgb)
        @canvas = Native.led_matrix_swap_on_vsync(@matrix, @canvas)
      end
    end

    def close
      @mutex.synchronize do
        return if @matrix.nil?

        Native.led_canvas_clear(@canvas)
        Native.led_matrix_swap_on_vsync(@matrix, @canvas)
        Native.led_matrix_delete(@matrix)
        @matrix = nil
      end
    end

    private

    def options
      Options.new.tap do |options|
        options[:hardware_mapping] = @hardware_mapping
        MATRIX_OPTIONS.except(:hardware_mapping).each { |field, value| options[field] = value }
      end
    end

    # Drop to daemon:daemon after init, as the Python binding does by default.
    def runtime_options
      RuntimeOptions.new.tap do |runtime|
        runtime[:gpio_slowdown] = GPIO_SLOWDOWN
        runtime[:drop_privileges] = 1
      end
    end
  end
end
