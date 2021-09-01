# frozen_string_literal: true

require 'timeout'

require 'mjai/logger'
require 'mjai/player'
require 'mjai/action'
require 'mjai/validation_error'

module Mjai
  class WebSocketPlayer < Player
    TIMEOUT_SEC = 60

    def initialize(websocket, name)
      super()
      @websocket = websocket
      self.name = name
      @line = nil
    end

    def receive(line)
      @line = line
    end

    def respond_to_action(action)
      Mjai::LOGGER.info("-> player #{id}\t#{action.to_json}")
      @websocket.send(action.to_json)
      @line = nil
      sleep 0.1 while @line.nil?
      if @line
        Mjai::LOGGER.info("<- player #{id}\t#{@line}")
        Action.from_json(@line.chomp, game)
      else
        Mjai::LOGGER.error("player #{id} has disconnected.")
        Action.new({ type: :none })
      end
    rescue Timeout::Error
      create_action({
                      type: :error,
                      message: "Timeout. No response in #{TIMEOUT_SEC} sec."
                    })
    rescue JSON::ParserError => e
      create_action({
                      type: :error,
                      message: "JSON syntax error: #{e.message}"
                    })
    rescue ValidationError => e
      create_action({
                      type: :error,
                      message: e.message
                    })
    end

    def close
      @websocket.close
    end
  end
end
