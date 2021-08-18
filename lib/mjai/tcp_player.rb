# frozen_string_literal: true

require 'timeout'

require 'mjai/player'
require 'mjai/action'
require 'mjai/validation_error'

module Mjai
  class TCPPlayer < Player
    TIMEOUT_SEC = 60

    def initialize(socket, name)
      super()
      @socket = socket
      self.name = name
    end

    def respond_to_action(action)
      puts(format("server -> player %d\t%s", id, action.to_json))
      @socket.puts(action.to_json)
      line = nil
      Timeout.timeout(TIMEOUT_SEC) do
        line = @socket.gets
      end
      if line
        puts(format("server <- player %d\t%s", id, line))
        Action.from_json(line.chomp, game)
      else
        puts('server :  Player %d has disconnected.' % id)
        Action.new({ type: :none })
      end
    rescue Timeout::Error
      create_action({
                      type: :error,
                      message: format('Timeout. No response in %d sec.', TIMEOUT_SEC)
                    })
    rescue JSON::ParserError => e
      create_action({
                      type: :error,
                      message: 'JSON syntax error: %s' % e.message
                    })
    rescue ValidationError => e
      create_action({
                      type: :error,
                      message: e.message
                    })
    end

    def close
      @socket.close
    end
  end
end
