# frozen_string_literal: true

require 'json'
require 'faye/websocket'
require './lib/mjai/active_game'
require './lib/mjai/active_test_game'
require './lib/mjai/ws_player'

# TCPGameServer#initialize()
# TCPGameServer#attr_reader(:params, :players, :num_finished_games)
params = {
  host: '0.0.0.0',
  port: 9292,
  room: 'default',
  game_type: 'one_kyoku',
  games: 'auto',
  log_dir: 'log',
  #  :player_commands => ['mjai_shanten', 'mjai_shanten', 'mjai_shanten']
  player_commands: []
}
players = []
mutex = Mutex.new
num_finished_games = 0

class LocalError < StandardError
end

server_url = "mjsonp://#{params[:host]}:#{params[:port]}/#{params[:room]}"
num_players = 4

Mjai::LOGGER.info("Listening on host #{params[:host]}, port #{params[:port]}")
Mjai::LOGGER.debug("URL:#{server_url}")
Mjai::LOGGER.info("Waiting for #{num_players} players...")

pids = []

# TCPGameServer#start_default_players()
params[:player_commands].each do |command|
  command += " #{server_url}"
  Mjai::LOGGER.info(command)
  pids.push(fork { exec(command) })
end

App = lambda do |env|
  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    player = Mjai::WebSocketPlayer.new(ws, "player#{players.size + 1}")
    ws.send({
              'type' => 'hello',
              'protocol' => 'mjsonp',
              'protocol_version' => 3
            })

    ws.on :message do |event|
      msg = JSON.parse(event.data, symbolize_names: true)
      begin
        if msg[:type] == 'join'
          raise(LocalError, "expected action type join but #{msg[:type]}") if msg[:type] != 'join'
          raise(LocalError, 'player name not found') unless msg[:name]
          raise(LocalError, 'room not found') unless msg[:room]
          raise(LocalError, "No such room found #{msg[:room]}") if msg[:room] != params[:room]

          mutex.synchronize do
            if players.size >= num_players
              Mjai::LOGGER.error('The room is busy. Retry after a while.')
              raise(LocalError, 'The room is busy. Retry after a while.')
            end
            player.name = (msg[:name]).to_s
            players.push(player)
            Mjai::LOGGER.info("Player #{player.name} joined")
            delta = num_players - players.size
            Mjai::LOGGER.info("Waiting for #{delta} more players...")
            if delta.zero?
              Thread.new do
                # TCPActiveGameServer#play_game()
                start_game(players)
                Mjai::LOGGER.debug('game ended')
              end
            end
          end
        else
          player.receive(event.data)
        end
      rescue LocalError => e
        Mjai::LOGGER.error(e.message)
        ws.close
      end
    end

    ws.on :close do |event|
      p [:close, event.code, event.reason]
      ws = nil
    end

    # Return async Rack response
    ws.rack_response

  else
    # Normal HTTP request
    [200, { 'Content-Type' => 'text/plain' }, ['Hello']]
  end
end

def start_game(players)
  # game = Mjai::ActiveTestGame.new(players, './scenarios/doubleriichi.scenario')
  game = Mjai::ActiveGame.new(players)
  # game.game_type = params[:game_type]
  # game.game_type = :one_kyoku
  game.game_type = :tonnan

  game.on_action do |action|
    game.dump_action(action)
  end
  game.play
  players.each(&:close)
  players.clear
  Mjai::LOGGER.debug('closed sockets')
end
