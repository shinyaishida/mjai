require 'uri'

require 'rubygems'
require 'json'
require 'faye/websocket'
require 'eventmachine'

require 'mjai/game'
require 'mjai/action'
require 'mjai/puppet_player'

module Mjai
  class WebSocketClientGame < Game
    def initialize(params)
      super()
      @params = params
    end

    def play
      EM.run do
        play_game
      end
    end

    def play_game
      uri = URI.parse(@params[:url])
      ws = Faye::WebSocket::Client.new(format('ws://%s:%d', uri.host, uri.port))

      ws.on :open do |_event|
        p [:open]
        ws.send(JSON.dump({
                            type: 'join',
                            name: 'client',
                            room: 'default'
                          }))
      end

      ws.on :close do |event|
        p [:close, event.code, event.reason]
        ws = nil
      end

      ws.on :message do |event|
        action_json = event.data
        puts(action_json)
        msg = JSON.parse(action_json, symbolize_names: true)
        case msg[:type]
        when 'hello'
          response_json = JSON.dump({
                                      'type' => 'join',
                                      'name' => @params[:name],
                                      'room' => uri.path.slice(%r{^/(.*)$}, 1)
                                    })
        when 'error'
          puts('ERROR: %s' % action_json)
          break
        else
          if msg[:type] == 'start_game'
            @my_id = msg[:id]
            self.players = Array.new(4) do |i|
              i == @my_id ? @params[:player] : PuppetPlayer.new
            end
          end
          action = Action.from_json(action_json, self)
          responses = do_action(action)
          break if action.type == :end_game

          response = responses && responses[@my_id]
          response_json = response ? response.to_json : JSON.dump({ 'type' => 'none' })
        end
        puts("->\t%s" % response_json)
        ws.send(response_json)
      end
      # # ふるいこーど
      # TCPSocket.open(uri.host, uri.port) do |socket|
      #   socket.sync = true
      #   socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      #   socket.each_line do |line|
      #     puts("<-\t%s" % line.chomp)
      #     action_json = line.chomp
      #     action_obj = JSON.parse(action_json)
      #     case action_obj['type']
      #     when 'hello'
      #       response_json = JSON.dump({
      #                                   'type' => 'join',
      #                                   'name' => @params[:name],
      #                                   'room' => uri.path.slice(%r{^/(.*)$}, 1)
      #                                 })
      #     when 'error'
      #       break
      #     else
      #       if action_obj['type'] == 'start_game'
      #         @my_id = action_obj['id']
      #         self.players = Array.new(4) do |i|
      #           i == @my_id ? @params[:player] : PuppetPlayer.new
      #         end
      #       end
      #       action = Action.from_json(action_json, self)
      #       responses = do_action(action)
      #       break if action.type == :end_game

      #       response = responses && responses[@my_id]
      #       response_json = response ? response.to_json : JSON.dump({ 'type' => 'none' })
      #     end
      #     puts("->\t%s" % response_json)
      #     socket.puts(response_json)
      #   end
      # end
    end

    def expect_response_from?(player)
      player.id == @my_id
    end
  end
end
