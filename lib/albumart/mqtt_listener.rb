# frozen_string_literal: true

require "mqtt"
require_relative "config"

module Albumart
  # Subscribes to the shairport-sync topics and hands each message to a block.
  # The mqtt gem does not reconnect on its own, so this loop does.
  class MqttListener
    TOPICS = [COVER_TOPIC, ARTIST_TOPIC, TITLE_TOPIC].freeze
    KEEP_ALIVE_SECONDS = 60
    FIRST_RETRY_SECONDS = 1
    MAX_RETRY_SECONDS = 30
    # MQTT::Exception derives from ::Exception, so it must be named explicitly.
    CONNECTION_ERRORS = [MQTT::Exception, SystemCallError, IOError, SocketError, Timeout::Error].freeze

    def initialize(host: BROKER, port: PORT, &on_message)
      @host = host
      @port = port
      @on_message = on_message
    end

    def run
      retry_in = FIRST_RETRY_SECONDS
      loop do
        MQTT::Client.connect(host: @host, port: @port, keep_alive: KEEP_ALIVE_SECONDS) do |client|
          Albumart.log("[mqtt] connected")
          retry_in = FIRST_RETRY_SECONDS
          client.subscribe(*TOPICS)
          client.get { |topic, payload| @on_message.call(topic, payload) }
        end
      rescue *CONNECTION_ERRORS => e
        Albumart.log("[mqtt] disconnected (#{e.class}: #{e.message}); retrying in #{retry_in}s")
        sleep(retry_in)
        retry_in = [retry_in * 2, MAX_RETRY_SECONDS].min
      end
    end
  end
end
