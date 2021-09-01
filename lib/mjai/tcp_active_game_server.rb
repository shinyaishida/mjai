# frozen_string_literal: true

require 'mjai/active_game'
require 'mjai/tcp_game_server'
require 'mjai/confidence_interval'
require 'mjai/file_converter'

module Mjai
  class TCPActiveGameServer < TCPGameServer
    Statistics = Struct.new(:num_games, :total_rank, :total_score, :ranks)

    def initialize(params)
      super
      @name_to_stat = {}
    end

    def num_tcp_players
      4
    end

    def play_game(players)
      mjson_path = "#{params[:log_dir]}/#{Time.now.strftime('%Y-%m-%d-%H%M%S')}.mjson" if params[:log_dir]
      game = nil
      success = false
      maybe_open(mjson_path, 'w') do |mjson_out|
        mjson_out.sync = true if mjson_out
        game = ActiveGame.new(players)
        game.game_type = params[:game_type]
        game.on_action do |action|
          game.dump_action(action)
        end
        game.on_responses do |action, _responses|
          # Logs on on_responses to include "logs" field.
          mjson_out&.puts(action.to_json)
        end
        success = game.play
      end

      FileConverter.new.convert(mjson_path, "#{mjson_path}.html") if mjson_path
      [game, success]
    end

    def on_game_succeed(game)
      puts(format('game %d: %s', num_finished_games, game.ranked_players.map do |pl|
                                                       format('%s:%d', pl.name, pl.score)
                                                     end.join(' ')))
      players.each do |player|
        @name_to_stat[player.name] ||= Statistics.new(0, 0, 0, [])
        @name_to_stat[player.name].num_games += 1
        @name_to_stat[player.name].total_score += player.score
        @name_to_stat[player.name].total_rank += player.rank
        @name_to_stat[player.name].ranks.push(player.rank)
      end
      names = players.map(&:name).sort.uniq
      print('Average rank:')
      names.each do |name|
        stat = @name_to_stat[name]
        rank_conf_interval = ConfidenceInterval.calculate(stat.ranks, min: 1.0, max: 4.0)
        print(format(' %s:%.3f [%.3f, %.3f]', name, stat.total_rank.to_f / stat.num_games, rank_conf_interval[0],
                     rank_conf_interval[1]))
      end
      puts
      print('Average score:')
      names.each do |name|
        print(format(' %s:%d', name, @name_to_stat[name].total_score.to_f / @name_to_stat[name].num_games))
      end
    end

    def on_game_fail(_game)
      puts('game %d: Ended with error' % num_finished_games)
    end

    def maybe_open(path, mode, &block)
      if path
        open(path, mode, &block)
      else
        yield(nil)
      end
    end
  end
end
