require 'socket'
require 'rubygems'
require 'json'
require 'mjai/tcp_player'

module Mjai
  class TCPGameServer
    class LocalError < StandardError
    end

    def initialize(params)
      @params = params
      @server = TCPServer.open(params[:host], params[:port])
      @players = []
      @mutex = Mutex.new
      @num_finished_games = 0
    end

    attr_reader(:params, :players, :num_finished_games)

    def run
      puts(format('Listening on host %s, port %d', @params[:host], port))
      puts('URL: %s' % server_url)
      puts('Waiting for %d players...' % num_tcp_players)
      @pids = []
      begin
        start_default_players
        while true
          Thread.new(@server.accept) do |socket|
            error = nil
            begin
              socket.sync = true
              socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
              send(socket, {
                     'type' => 'hello',
                     'protocol' => 'mjsonp',
                     'protocol_version' => 3
                   })
              line = socket.gets
              raise(LocalError, 'Connection closed') unless line

              puts("server <- player ?\t#{line}")
              message = JSON.parse(line)
              if message['type'] != 'join' || !message['name'] || !message['room']
                raise(LocalError, 'Expected e.g. %s' %
                    JSON.dump({ 'type' => 'join', 'name' => 'noname', 'room' => @params[:room] }))
              end
              if message['room'] != @params[:room]
                raise(LocalError, 'No such room. Available room: %s' % @params[:room])
              end

              @mutex.synchronize do
                raise(LocalError, 'The room is busy. Retry after a while.') if @players.size >= num_tcp_players

                @players.push(TCPPlayer.new(socket, message['name']))
                puts(format('Waiting for %s more players...', (num_tcp_players - @players.size)))
                Thread.new { process_one_game } if @players.size == num_tcp_players
              end
            rescue JSON::ParserError => e
              error = 'JSON syntax error: %s' % e.message
            rescue SystemCallError => e
              error = e.message
            rescue LocalError => e
              error = e.message
            end
            if error
              begin
                send(socket, { 'type' => 'error', 'message' => error })
                socket.close
              rescue SystemCallError
              end
            end
          end
        end
      rescue Exception => e
        @pids.each do |pid|
          Process.kill('INT', pid)
        rescue StandardError => ex2
          p ex2
        end
        raise(e)
      end
    end

    def process_one_game
      game = nil
      success = false
      begin
        (game, success) = play_game(@players)
      rescue StandardError => e
        print_backtrace(e)
      end

      begin
        @players.each do |player|
          player.close
        end
      rescue StandardError => e
        print_backtrace(e)
      end

      begin
        @pids.each do |pid|
          Process.waitpid(pid)
        end
      rescue StandardError => e
        print_backtrace(e)
      end

      @num_finished_games += 1

      if success
        on_game_succeed(game)
      else
        on_game_fail(game)
      end
      puts

      @pids = []
      @players = []
      if @num_finished_games >= @params[:num_games]
        exit
      else
        start_default_players
      end
    end

    def server_url
      format('mjsonp://localhost:%d/%s', port, @params[:room])
    end

    def port
      @server.addr[1]
    end

    def start_default_players
      @params[:player_commands].each do |command|
        command += ' ' + server_url
        puts(command)
        @pids.push(fork { exec(command) })
      end
    end

    def send(socket, hash)
      line = JSON.dump(hash)
      puts("server -> player ?\t#{line}")
      socket.puts(line)
    end

    def print_backtrace(ex, io = $stderr)
      io.printf("%s: %s (%p)\n", ex.backtrace[0], ex.message, ex.class)
      ex.backtrace[1..-1].each do |s|
        io.printf("        %s\n", s)
      end
    end
  end
end
