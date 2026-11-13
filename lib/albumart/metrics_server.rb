# frozen_string_literal: true

require "falcon"
require "async/http/endpoint"
require "protocol/http/middleware"
require "prometheus/client"
require "prometheus/client/formats/text"
require_relative "config"
require_relative "scheduler"

module Albumart
  # Serves GET /metrics in the Prometheus text format with Falcon. The port is
  # bound in .new, so bind errors surface there rather than in #start.
  class MetricsServer
    PATH = "/metrics"
    CONTENT_TYPE = "#{Prometheus::Client::Formats::Text::CONTENT_TYPE}; charset=utf-8".freeze

    def initialize(stats:, port: METRICS_PORT, bind: METRICS_BIND)
      @stats = stats
      @endpoint = Async::HTTP::Endpoint.parse("http://#{bind}:#{port}")
      @bound = @endpoint.bound
      @port = @bound.sockets.first.local_address.ip_port
      @stop = Thread::Queue.new
      @mutex = Mutex.new
      @state = :idle
    end

    attr_reader :port

    def start
      @mutex.synchronize do
        return unless @state == :idle

        @state = :running
      end
      begin
        serve
      ensure
        @bound.close
      end
    end

    # Closes the socket itself only when #start is not serving; a running #start closes it on the way out.
    def shutdown
      @mutex.synchronize do
        @stop.close
        if @state == :idle
          @state = :stopped
          @bound.close
        end
      end
    end

    private

    def serve
      Sync do |task|
        server = Falcon::Server.new(application, @bound, protocol: @endpoint.protocol, scheme: @endpoint.scheme)
        server_task = server.run
        task.async(transient: true) do
          @stop.pop
          server_task.stop
        end
        server_task.wait
      end
    end

    def application
      Protocol::HTTP::Middleware.for { |request| respond(request) }
    end

    def respond(request)
      return Protocol::HTTP::Response[404, {}, []] unless request.path.split("?", 2).first == PATH

      body = Prometheus::Client::Formats::Text.marshal(registry_for(@stats.snapshot))
      Protocol::HTTP::Response[200, { "content-type" => CONTENT_TYPE }, [body]]
    rescue StandardError
      Protocol::HTTP::Response[500, {}, []]
    end

    # A fresh registry per scrape: counters can then be set to the snapshot's totals, and
    # label-less gauges, which the gem always initialises to 0, can be left out when unknown.
    def registry_for(snapshot)
      registry = Prometheus::Client::Registry.new
      gauge(registry, :albumart_uptime_seconds, "Seconds since the display started", snapshot.uptime_seconds)
      gauge(registry, :albumart_last_cover_age_seconds, "Seconds since the last cover", snapshot.last_cover_age_seconds)
      counter(registry, :albumart_covers_total, "Covers received", snapshot.covers_total)
      gauge(registry, :albumart_mqtt_connected, "1 while connected to the MQTT broker", snapshot.mqtt_connected ? 1 : 0)
      counter(registry, :albumart_mqtt_connects_total, "MQTT connections made", snapshot.mqtt_connects_total)
      counter(registry, :albumart_mqtt_disconnects_total, "MQTT disconnects and failed connects",
              snapshot.mqtt_disconnects_total)
      gauge(registry, :albumart_weather_age_seconds, "Seconds since the last successful weather fetch",
            snapshot.weather_age_seconds)
      counter(registry, :albumart_weather_fetch_errors_total, "Failed weather fetches",
              snapshot.weather_fetch_errors_total)
      gauge(registry, :albumart_snow_age_seconds, "Seconds since the last successful snow report fetch",
            snapshot.snow_age_seconds)
      counter(registry, :albumart_snow_fetch_errors_total, "Failed snow report fetches",
              snapshot.snow_fetch_errors_total)
      slides = registry.gauge(:albumart_current_slide, docstring: "1 for the slide on the panel", labels: [:slide])
      Scheduler::SLIDES.each { |slide| slides.set(slide == snapshot.current_slide ? 1 : 0, labels: { slide: }) }
      registry
    end

    def gauge(registry, name, docstring, value)
      return if value.nil?

      registry.gauge(name, docstring:).set(value)
    end

    def counter(registry, name, docstring, total)
      registry.counter(name, docstring:).increment(by: total)
    end
  end
end
