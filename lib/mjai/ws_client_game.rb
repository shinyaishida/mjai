# frozen_string_literal: true

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
      @uri = URI.parse(@params[:url])
      @server = "ws://#{@uri.host}:#{@uri.port}"
      @ws = nil
      @connected = false
    end

    def play
      EM.run { play_game }
    end

    private

    def play_game
      @ws = Faye::WebSocket::Client.new(@server)
      @ws.on :open do |_event|
        @connected = true
        p [:open]
        @ws.send(JSON.dump({
                             type: 'join',
                             name: @params[:name],
                             room: 'default'
                           }))
      end

      @ws.on :close do |event|
        if @connected
          p [:close, event.code, event.reason]
          @connected = false
        else
          puts "connecting to #{@server}"
        end
        @ws = nil
        EM.stop_event_loop
      end

      @ws.on :message do |event|
        action_json = event.data
        puts(action_json)
        msg = JSON.parse(action_json, symbolize_names: true)
        case msg[:type]
        when 'hello'
          response_json = JSON.dump({
                                      'type' => 'join',
                                      'name' => @params[:name],
                                      'room' => @uri.path.slice(%r{^/(.*)$}, 1)
                                    })
        when 'error'
          puts("ERROR: #{action_json}")
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
        puts("->\t#{response_json}")
        @ws.send(response_json)
      end
    end

    def expect_response_from?(player)
      player.id == @my_id
    end
  end
end
