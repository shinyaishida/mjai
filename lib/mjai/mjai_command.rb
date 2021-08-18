# frozen_string_literal: true

require 'optparse'

require 'mjai/tcp_active_game_server'
require 'mjai/tcp_client_game'
require 'mjai/ws_client_game'
require 'mjai/tsumogiri_player'
require 'mjai/shanten_player'
require 'mjai/file_converter'
require 'mjai/game_stats'

module Mjai
  class MjaiCommand
    def self.execute(command_name, argv)
      Thread.abort_on_exception = true
      case command_name

      when 'mjai'

        action = argv.shift
        opts = OptionParser.getopts(argv, '',
                                    'port:11600', 'host:127.0.0.1', 'room:default', 'game_type:one_kyoku',
                                    'games:auto', 'repeat', 'log_dir:', 'output_type:')

        case action

        when 'server'
          $stdout.sync = true
          player_commands = argv
          if opts['repeat']
            warn('--repeat is deprecated. Use --games=inifinite instead.')
            exit(1)
          end
          num_games = case opts['games']
                      when 'auto'
                        player_commands.size == 4 ? 1 : 1.0 / 0.0
                      when 'infinite'
                        1.0 / 0.0
                      else
                        opts['games'].to_i
                      end
          server = TCPActiveGameServer.new({
                                             host: opts['host'],
                                             port: opts['port'].to_i,
                                             room: opts['room'],
                                             game_type: opts['game_type'].intern,
                                             player_commands: player_commands,
                                             num_games: num_games,
                                             log_dir: opts['log_dir']
                                           })
          server.run

        when 'convert'
          conv = FileConverter.new
          if opts['output_type']
            argv.each do |pattern|
              paths = Dir[pattern]
              if paths.empty?
                warn('No match: %s' % pattern)
                exit(1)
              end
              paths.each do |path|
                conv.convert(path, "#{path}.#{opts['output_type']}")
              end
            end
          else
            conv.convert(argv.shift, argv.shift)
          end

        when 'stats'
          GameStats.print(argv)

        else
          warn(
            "Basic Usage:\n" \
              "  #{$PROGRAM_NAME} server --port=PORT\n" \
              "  #{$PROGRAM_NAME} server --port=PORT " \
                  "[PLAYER1_COMMAND] [PLAYER2_COMMAND] [...]\n" \
              "  #{$PROGRAM_NAME} stats 1.mjson [2.mjson] [...]\n" \
              "  #{$PROGRAM_NAME} convert hoge.mjson hoge.html\n" \
              "  #{$PROGRAM_NAME} convert hoge.mjlog hoge.mjson\n\n" \
              "Complete usage:\n" \
              "  #{$PROGRAM_NAME} server \\\n" \
              "    --host=IP_ADDRESS \\\n" \
              "    --port=PORT \\\n" \
              "    --room=ROOM_NAME \\\n" \
              "    --game_type={one_kyoku|tonpu|tonnan} \\\n" \
              "    --games={NUM_GAMES|infinite} \\\n" \
              "    --log_dir=LOG_DIR_PATH \\\n" \
              "    [PLAYER1_COMMAND] [PLAYER2_COMMAND] [...]\n\n" \
              "See here for details:\n" \
              'http://gimite.net/pukiwiki/index.php?' \
              "Mjai%20%CB%E3%BF%FDAI%C2%D0%C0%EF%A5%B5%A1%BC%A5%D0\n"
          )
          exit(1)

        end

      when /^mjai-(.+)$/

        $stdout.sync = true
        $stderr.sync = true
        player_type = Regexp.last_match(1)
        opts = OptionParser.getopts(argv, '', 't:', 'name:')
        url = ARGV.shift

        unless url
          warn(
            "Usage:\n" \
              "  #{$PROGRAM_NAME} mjsonp://localhost:11600/default\n"
          )
          exit(1)
        end
        case player_type
        when 'tsumogiri'
          player = TsumogiriPlayer.new
        when 'shanten'
          player = Mjai::ShantenPlayer.new({ use_furo: opts['t'] == 'f' })
        else
          raise('should not happen')
        end
        game = WebSocketClientGame.new({
                                         player: player,
                                         url: url,
                                         name: opts['name'] || player_type
                                       })
        Kernel.loop do
          game.play
          sleep 5.0
        end
      else
        raise('should not happen')
      end
    end
  end
end
