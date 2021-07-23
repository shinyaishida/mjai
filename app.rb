require 'json'
require 'faye/websocket'
require './lib/mjai/active_game'
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

# TCPGameServer#server_url()
server_url = format('mjsonp://%s:%d/%s', params[:host], params[:port], params[:room])

# TCPActiveGameServer#num_tcp_players()
num_tcp_players = 4

puts(format('Listening on host %s, port %d', params[:host], params[:port]))
puts('URL: %s' % server_url)
puts('Waiting for %d players...' % num_tcp_players)

pids = []

# TCPGameServer#start_default_players()
params[:player_commands].each do |command|
  command += ' ' + server_url
  puts(command)
  pids.push(fork { exec(command) })
end

App = lambda do |env|
  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    player = Mjai::WebSocketPlayer.new(ws, format('player%d', players.length + 1))

    ws.send({
              'type' => 'hello',
              'protocol' => 'mjsonp',
              'protocol_version' => 3
            })

    ws.on :message do |event|
      puts("server <- player ?\t#{event.data}")
      msg = JSON.parse(event.data, symbolize_names: true)
      begin
        if msg[:type] == 'join'
          raise(LocalError, 'expected action type join but %s' % msg[:type]) if msg[:type] != 'join'
          raise(LocalError, 'player name not found') unless msg[:name]
          raise(LocalError, 'room not found') unless msg[:room]
          raise(LocalError, 'No such room found %s' % msg[:room]) if msg[:room] != params[:room]

          mutex.synchronize do
            if players.size >= num_tcp_players
              puts('ERROR: The room is busy. Retry after a while.')
              raise(LocalError, 'The room is busy. Retry after a while.')
            end
            players.push(player)
            delta = num_tcp_players - players.size
            puts('Waiting for %s more players...' % delta)
            if delta == 0
              Thread.new do
                # TCPActiveGameServer#play_game()
                success = start_game(players)
                puts success
              end
            end
          end
        else
          player.receive(event.data)
        end
      rescue LocalError => e
        error = e.message
        puts('ERROR: %s' % error)
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
  game = Mjai::ActiveGame.new(players)
  #  game.game_type = params[:game_type]
  game.game_type = :one_kyoku
  game.on_action do |action|
    game.dump_action(action)
  end
  game.play
end
