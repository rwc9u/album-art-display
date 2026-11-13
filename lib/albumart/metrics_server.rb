# frozen_string_literal: true

require "webrick"
require "prometheus/client"
require "prometheus/client/formats/text"
require_relative "config"
require_relative "scheduler"

module Albumart
  # Serves GET /metrics in the Prometheus text format. WEBrick binds the port in
  # .new, so bind errors surface there rather than in #start.
  class MetricsServer
    PATH = "/metrics"
    CONTENT_TYPE = "#{Prometheus::Client::Formats::Text::CONTENT_TYPE}; charset=utf-8".freeze

    def initialize(stats:, port: METRICS_PORT, bind: METRICS_BIND)
      @stats = stats
      @server = WEBrick::HTTPServer.new(
        BindAddress: bind,
        Port: port,
        AccessLog: [],
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
        DoNotReverseLookup: true,
      )
      @server.mount_proc("/") { |request, response| respond(request, response) }
    end

    def start
      @server.start
    end

    def shutdown
      @server.shutdown
    end

    def port
      @server.config[:Port]
    end

    private

    # Setting 404 directly, rather than raising NotFound, keeps WEBrick from logging stray requests.
    def respond(request, response)
      unless request.path == PATH
        response.status = 404
        return
      end

      response.content_type = CONTENT_TYPE
      response.body = Prometheus::Client::Formats::Text.marshal(registry_for(@stats.snapshot))
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
