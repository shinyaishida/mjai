# frozen_string_literal: true

require 'mjai/archive'
require 'mjai/confidence_interval'

module Mjai
  class GameStats
    YAKU_JA_NAMES = {
      menzenchin_tsumoho: '面前清自摸和', riichi: '立直', ippatsu: '一発',
      chankan: '槍槓', rinshankaiho: '嶺上開花', haiteiraoyue: '海底摸月',
      hoteiraoyui: '河底撈魚', pinfu: '平和', tanyaochu: '断么九',
      ipeko: '一盃口', jikaze: '面風牌', bakaze: '圏風牌',
      sangenpai: '三元牌', double_riichi: 'ダブル立直', chitoitsu: '七対子',
      honchantaiyao: '混全帯么九', ikkitsukan: '一気通貫',
      sanshokudojun: '三色同順', sanshokudoko: '三色同刻', sankantsu: '三槓子',
      toitoiho: '対々和', sananko: '三暗刻', shosangen: '小三元',
      honroto: '混老頭', ryanpeko: '二盃口', junchantaiyao: '純全帯么九',
      honiso: '混一色', chiniso: '清一色', renho: '人和', tenho: '天和',
      chiho: '地和', daisangen: '大三元', suanko: '四暗刻',
      tsuiso: '字一色', ryuiso: '緑一色', chinroto: '清老頭',
      churenpoton: '九蓮宝燈', kokushimuso: '国士無双',
      daisushi: '大四喜', shosushi: '小四喜', sukantsu: '四槓子',
      dora: 'ドラ', uradora: '裏ドラ', akadora: '赤ドラ'
    }.freeze

    def self.print(mjson_paths)
      num_errors = 0
      name_to_ranks = {}
      name_to_scores = {}
      name_to_kyoku_count = {}
      name_to_hora_count = {}
      name_to_yaku_stats = {}
      name_to_dora_stats = {}
      name_to_hoju_count = {}
      name_to_furo_kyoku_count = {}
      name_to_riichi_count = {}
      name_to_hora_points = {}

      mjson_paths.each do |path|
        archive = Archive.load(path)
        first_action = archive.raw_actions[0]
        last_action = archive.raw_actions[-1]
        if !last_action || last_action.type != :end_game
          num_errors += 1
          next
        end
        archive.do_action(first_action)

        scores = last_action.scores
        id_to_name = first_action.names

        chicha_id = archive.raw_actions[1].oya.id
        ranked_player_ids =
          (0...4).sort_by { |i| [-scores[i], (i + 4 - chicha_id) % 4] }
        (0...4).each do |r|
          name = id_to_name[ranked_player_ids[r]]
          name_to_ranks[name] ||= []
          name_to_ranks[name].push(r + 1)
        end

        (0...4).each do |p|
          name = id_to_name[p]
          name_to_scores[name] ||= []
          name_to_scores[name].push(scores[p])
        end

        # Kyoku specific fields.
        id_to_done_riichi = {}
        id_to_done_furo = {}
        archive.raw_actions.each do |raw_action|
          if raw_action.type == :hora
            name = id_to_name[raw_action.actor.id]
            name_to_hora_count[name] ||= 0
            name_to_hora_count[name] += 1
            name_to_hora_points[name] ||= []
            name_to_hora_points[name].push(raw_action.hora_points)
            raw_action.yakus.each do |yaku, fan|
              if %i[dora akadora uradora].include?(yaku)
                name_to_dora_stats[name] ||= {}
                name_to_dora_stats[name][yaku] ||= 0
                name_to_dora_stats[name][yaku] += fan
                next
              end
              name_to_yaku_stats[name] ||= {}
              name_to_yaku_stats[name][yaku] ||= 0
              name_to_yaku_stats[name][yaku] += 1
            end
            if raw_action.actor.id != raw_action.target.id
              target_name = id_to_name[raw_action.target.id]
              name_to_hoju_count[target_name] ||= 0
              name_to_hoju_count[target_name] += 1
            end
          end
          id_to_done_riichi[raw_action.actor.id] = true if raw_action.type == :riichi_accepted
          id_to_done_furo[raw_action.actor.id] = true if raw_action.type == :pon
          id_to_done_furo[raw_action.actor.id] = true if raw_action.type == :chi
          id_to_done_furo[raw_action.actor.id] = true if raw_action.type == :daiminkan
          next unless raw_action.type == :end_kyoku

          (0...4).each do |p|
            name = id_to_name[p]

            if id_to_done_furo[p]
              name_to_furo_kyoku_count[name] ||= 0
              name_to_furo_kyoku_count[name] += 1
            end
            if id_to_done_riichi[p]
              name_to_riichi_count[name] ||= 0
              name_to_riichi_count[name] += 1
            end

            name_to_kyoku_count[name] ||= 0
            name_to_kyoku_count[name] += 1
          end

          # Reset kyoku specific fields.
          id_to_done_furo = {}
          id_to_done_riichi = {}
        end
      end
      puts(format('errors: %d / %d', num_errors, mjson_paths.size)) if num_errors.positive?

      puts('Average ranks:')
      name_to_ranks.sort.each do |name, ranks|
        rank_conf_interval = ConfidenceInterval.calculate(ranks, min: 1.0, max: 4.0)
        puts(format('  %s: %.3f [%.3f, %.3f]', name, ranks.inject(0, :+).to_f / ranks.size, rank_conf_interval[0],
                    rank_conf_interval[1]))
      end
      puts

      puts('Rank distributions:')
      name_to_ranks.sort.each do |name, ranks|
        puts(format('  %s: %s', name, (1..4).map { |i| format('[%d] %d', i, ranks.count(i)) }.join('  ')))
      end
      puts

      puts('Average scores:')
      name_to_scores.sort.each do |name, scores|
        puts(format('  %s: %d', name, scores.inject(0, :+).to_i / scores.size))
      end
      puts

      puts('Hora rates:')
      name_to_hora_count.sort.each do |name, hora_count|
        puts(format('  %s: %.1f%%', name, 100.0 * hora_count / name_to_kyoku_count[name]))
      end
      puts

      puts('Hoju rates:')
      name_to_hoju_count.sort.each do |name, hoju_count|
        puts(format('  %s: %.1f%%', name, 100.0 * hoju_count / name_to_kyoku_count[name]))
      end
      puts

      puts('Furo rates:')
      name_to_furo_kyoku_count.sort.each do |name, furo_kyoku_count|
        puts(format('  %s: %.1f%%', name, 100.0 * furo_kyoku_count / name_to_kyoku_count[name]))
      end
      puts

      puts('Riichi rates:')
      name_to_riichi_count.sort.each do |name, riichi_count|
        puts(format('  %s: %.1f%%', name, 100.0 * riichi_count / name_to_kyoku_count[name]))
      end
      puts

      puts('Average hora points:')
      name_to_hora_points.sort.each do |name, hora_points|
        puts(format('  %s: %d', name, hora_points.inject(0, :+).to_i / hora_points.size))
      end
      puts

      puts('Yaku stats:')
      name_to_yaku_stats.sort.each do |name, yaku_stats|
        hora_count = name_to_hora_count[name]
        puts(format('  %s (%d horas):', name, hora_count))
        yaku_stats.sort_by { |_yaku, count| -count }.each do |yaku, count|
          yaku_name = YAKU_JA_NAMES[yaku]
          puts(format('    %s: %d (%.1f%%)', yaku_name, count, 100.0 * count / hora_count))
        end
      end
      puts

      puts('Dora stats:')
      name_to_dora_stats.sort.each do |name, dora_stats|
        hora_count = name_to_hora_count[name]
        puts(format('  %s (%d horas):', name, hora_count))
        dora_stats.sort_by { |_dora, count| -count }.each do |dora, count|
          dora_name = YAKU_JA_NAMES[dora]
          puts(format('    %s: %d (%.3f/hora)', dora_name, count, count.to_f / hora_count))
        end
      end
      puts
    end
  end
end
