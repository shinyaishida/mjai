# frozen_string_literal: true

# Reference: http://tenhou.net/1/script/tenhou.js

require 'zlib'
require 'uri'
require 'nokogiri'

require 'mjai/archive'
require 'mjai/pai'
require 'mjai/action'
require 'mjai/puppet_player'

module Mjai
  class TenhouArchive < Archive
    module Util
      YAKU_ID_TO_NAME = %i[
        menzenchin_tsumoho reach ippatsu chankan rinshankaiho
        haiteiraoyue hoteiraoyui pinfu tanyaochu ipeko
        jikaze jikaze jikaze jikaze
        bakaze bakaze bakaze bakaze
        sangenpai sangenpai sangenpai
        double_reach chitoitsu honchantaiyao ikkitsukan sanshokudojun
        sanshokudoko sankantsu toitoiho sananko shosangen honroto
        ryanpeko junchantaiyao honiso
        chiniso
        renho
        tenho chiho daisangen suanko suanko tsuiso
        ryuiso chinroto churenpoton churenpoton kokushimuso
        kokushimuso daisushi shosushi sukantsu
        dora uradora akadora
      ].freeze

      def on_tenhou_event(elem, _next_elem = nil)
        verify_tenhou_tehais if @first_kyoku_started
        case elem.name
        when 'GO'
          raise(Archive::UnsupportedArchiveError, 'Sanma is not supported.') if elem['type'].to_i & 16 != 0 # Sanma.
        when 'SHUFFLE', 'BYE'
          # BYE: log out
          nil
        when 'UN'
          unless @names # Somehow there can be multiple UN's.
            escaped_names = (0...4).map { |i| elem['n%d' % i] }
            return :broken if escaped_names.index(nil) # Something is wrong.

            @names = escaped_names.map { |s| URI.decode(s) }
          end
          nil
        when 'TAIKYOKU'
          oya = elem['oya'].to_i
          log_name = elem['log'] || File.basename(path, '.mjlog')
          uri = format('http://tenhou.net/0/?log=%s&tw=%d', log_name, (4 - oya) % 4)
          @first_kyoku_started = false
          do_action({ type: :start_game, uri: uri, names: @names })
        when 'INIT'
          if @first_kyoku_started
            # Ends the previous kyoku. This is here because there can be multiple AGARIs in
            # case of daburon, so we cannot detect the end of kyoku in AGARI.
            do_action({ type: :end_kyoku })
          end
          (kyoku_id, honba, _, _, _, dora_marker_pid) = elem['seed'].split(/,/).map(&:to_i)
          bakaze = Pai.new('t', kyoku_id / 4 + 1)
          kyoku_num = kyoku_id % 4 + 1
          oya = elem['oya'].to_i
          @first_kyoku_started = true
          tehais_list = []
          (0...4).each do |i|
            hai_str = if i.zero?
                        elem['hai'] || elem['hai0']
                      else
                        elem['hai%d' % i]
                      end
            pids = hai_str ? hai_str.split(/,/) : [nil] * 13
            players[i].attributes.tenhou_tehai_pids = pids
            tehais_list.push(pids.map { |s| pid_to_pai(s) })
          end
          do_action({
                      type: :start_kyoku,
                      bakaze: bakaze,
                      kyoku: kyoku_num,
                      honba: honba,
                      oya: players[oya],
                      dora_marker: pid_to_pai(dora_marker_pid.to_s),
                      tehais: tehais_list
                    })
          nil
        when /^([T-W])(\d+)?$/i
          player_id = %w[T U V W].index(Regexp.last_match(1).upcase)
          pid = Regexp.last_match(2)
          players[player_id].attributes.tenhou_tehai_pids.push(pid)
          do_action({
                      type: :tsumo,
                      actor: players[player_id],
                      pai: pid_to_pai(pid)
                    })
        when /^([D-G])(\d+)?$/i
          prefix = Regexp.last_match(1)
          pid = Regexp.last_match(2)
          player_id = %w[D E F G].index(prefix.upcase)
          tsumogiri = if pid && pid == players[player_id].attributes.tenhou_tehai_pids[-1]
                        true
                      else
                        prefix != prefix.upcase
                      end
          delete_tehai_by_pid(players[player_id], pid)
          do_action({
                      type: :dahai,
                      actor: players[player_id],
                      pai: pid_to_pai(pid),
                      tsumogiri: tsumogiri
                    })
        when 'REACH'
          actor = players[elem['who'].to_i]
          case elem['step']
          when '1'
            do_action({ type: :reach, actor: actor })
          when '2'
            deltas = [0, 0, 0, 0]
            deltas[actor.id] = -1000
            # Old Tenhou archive doesn't have "ten" attribute. Calculates it manually.
            scores = (0...4).map do |i|
              players[i].score + deltas[i]
            end
            do_action({
                        type: :reach_accepted,
                        actor: actor,
                        deltas: deltas,
                        scores: scores
                      })
          else
            raise('should not happen')
          end
        when 'AGARI'
          tehais = (elem['hai'].split(/,/) - [elem['machi']]).map { |pid| pid_to_pai(pid) }
          points_params = get_points_params(elem['sc'])
          (fu, hora_points,) = elem['ten'].split(/,/).map(&:to_i)
          fan = if elem['yakuman']
                  Hora::YAKUMAN_FAN
                else
                  elem['yaku'].split(/,/).each_slice(2).map { |_y, f| f.to_i }.inject(0, :+)
                end
          uradora_markers = (elem['doraHaiUra'] || '')
                            .split(/,/).map { |pid| pid_to_pai(pid) }

          yakus = if elem['yakuman']
                    elem['yakuman']
                      .split(/,/)
                      .map { |y| [YAKU_ID_TO_NAME[y.to_i], Hora::YAKUMAN_FAN] }
                  else
                    elem['yaku']
                      .split(/,/)
                      .enum_for(:each_slice, 2)
                      .map { |y, f| [YAKU_ID_TO_NAME[y.to_i], f.to_i] }
                      .reject { |_y, f| f.zero? }
                  end

          pao = elem['paoWho']

          do_action({
            type: :hora,
            actor: players[elem['who'].to_i],
            target: players[elem['fromWho'].to_i],
            pai: pid_to_pai(elem['machi']),
            hora_tehais: tehais,
            uradora_markers: uradora_markers,
            fu: fu,
            fan: fan,
            yakus: yakus,
            hora_points: hora_points,
            deltas: points_params[:deltas],
            scores: points_params[:scores]
          }.merge(!pao.nil? ? { pao: players[pao.to_i] } : {}))
          if elem['owari']
            do_action({ type: :end_kyoku })
            do_action({ type: :end_game, scores: points_params[:scores] })
          end
          nil
        when 'RYUUKYOKU'
          points_params = get_points_params(elem['sc'])
          tenpais = []
          tehais = []
          (0...4).each do |i|
            name = 'hai%d' % i
            if elem[name]
              tenpais.push(true)
              tehais.push(elem[name].split(/,/).map { |pid| pid_to_pai(pid) })
            else
              tenpais.push(false)
              tehais.push([Pai::UNKNOWN] * players[i].tehais.size)
            end
          end
          reason_map = {
            'yao9' => :kyushukyuhai,
            'kaze4' => :sufonrenta,
            'reach4' => :suchareach,
            'ron3' => :sanchaho,
            'nm' => :nagashimangan,
            'kan4' => :sukaikan,
            nil => :fanpai
          }
          reason = reason_map[elem['type']]
          raise('unknown reason') unless reason

          # TODO: add actor for some reasons
          do_action({
                      type: :ryukyoku,
                      reason: reason,
                      tenpais: tenpais,
                      tehais: tehais,
                      deltas: points_params[:deltas],
                      scores: points_params[:scores]
                    })
          if elem['owari']
            do_action({ type: :end_kyoku })
            do_action({ type: :end_game, scores: points_params[:scores] })
          end
          nil
        when 'N'
          actor = players[elem['who'].to_i]
          furo = TenhouFuro.new(elem['m'].to_i)
          consumed_pids = furo.type == :kakan ? [furo.taken_pid] : furo.consumed_pids
          consumed_pids.each do |pid|
            delete_tehai_by_pid(actor, pid)
          end
          do_action(furo.to_action(self, actor))
        when 'DORA'
          do_action({ type: :dora, dora_marker: pid_to_pai(elem['hai']) })
          nil
        when 'FURITEN'
          nil
        else
          raise('unknown tag name: %s' % elem.name)
        end
      end

      def path
        nil
      end

      def get_points_params(sc_str)
        sc_nums = sc_str.split(/,/).map(&:to_i)
        result = {}
        result[:deltas] = (0...4).map { |i| sc_nums[2 * i + 1] * 100 }
        result[:scores] =
          (0...4).map { |i| sc_nums[2 * i] * 100 + result[:deltas][i] }
        result
      end

      def delete_tehai_by_pid(player, pid)
        idx = player.attributes.tenhou_tehai_pids.index { |tp| !tp || tp == pid }
        raise(format('%d not found in %p', pid, player.attributes.tenhou_tehai_pids)) unless idx

        player.attributes.tenhou_tehai_pids.delete_at(idx)
      end

      def verify_tenhou_tehais
        players.each do |player|
          next unless player.tehais

          tenhou_tehais =
            player.attributes.tenhou_tehai_pids.map { |pid| pid_to_pai(pid) }.sort
          tehais = player.tehais.sort
          raise(format('tenhou_tehais != tehais: %p != %p', tenhou_tehais, tehais)) if tenhou_tehais != tehais
        end
      end

      module_function

      def pid_to_pai(pid)
        pid ? get_pai(*decompose_pid(pid)) : Pai::UNKNOWN
      end

      def decompose_pid(pid)
        pid = pid.to_i
        [
          (pid / 4) / 9,
          (pid / 4) % 9 + 1,
          pid % 4
        ]
      end

      def compose_pid(type_id, number, cid)
        ((type_id * 9 + (number - 1)) * 4 + cid).to_s
      end

      def get_pai(type_id, number, cid)
        type = %w[m p s t][type_id]
        # TODO: only for games with red 5p
        red = type != 't' && number == 5 && cid.zero?
        Pai.new(type, number, red)
      end
    end

    # http://p.tenhou.net/img/mentsu136.txt
    class TenhouFuro
      include(Util)

      def initialize(fid)
        @num = fid
        @target_dir = read_bits(2)
        if read_bits(1) == 1
          parse_chi
          return
        end
        if read_bits(1) == 1
          parse_pon
          return
        end
        if read_bits(1) == 1
          parse_kakan
          return
        end
        if read_bits(1) == 1
          parse_nukidora
          return
        end
        parse_kan
      end

      attr_reader(:type, :target_dir, :taken_pid, :consumed_pids)

      def to_action(game, actor)
        params = {
          type: @type,
          actor: actor,
          pai: pid_to_pai(@taken_pid),
          consumed: @consumed_pids.map { |pid| pid_to_pai(pid) }
        }
        params[:target] = game.players[(actor.id + @target_dir) % 4] unless %i[ankan kakan].include?(@type)
        Action.new(params)
      end

      def parse_chi
        cids = (0...3).map { |_i| read_bits(2) }
        read_bits(1)
        pattern = read_bits(6)
        seq_kind = pattern / 3
        taken_pos = pattern % 3
        pai_type = seq_kind / 7
        first_number = seq_kind % 7 + 1
        @type = :chi
        @consumed_pids = []
        (0...3).each do |i|
          pid = compose_pid(pai_type, first_number + i, cids[i])
          if i == taken_pos
            @taken_pid = pid
          else
            @consumed_pids.push(pid)
          end
        end
      end

      def parse_pon
        read_bits(1)
        unused_cid = read_bits(2)
        read_bits(2)
        pattern = read_bits(7)
        pai_kind = pattern / 3
        taken_pos = pattern % 3
        pai_type = pai_kind / 9
        pai_number = pai_kind % 9 + 1
        @type = :pon
        @consumed_pids = []
        j = 0
        (0...4).each do |i|
          next if i == unused_cid

          pid = compose_pid(pai_type, pai_number, i)
          if j == taken_pos
            @taken_pid = pid
          else
            @consumed_pids.push(pid)
          end
          j += 1
        end
      end

      def parse_kan
        read_bits(2)
        pid = read_bits(8)
        (pai_type, pai_number, key_cid) = decompose_pid(pid)
        @type = @target_dir.zero? ? :ankan : :daiminkan
        @consumed_pids = []
        (0...4).each do |i|
          pid = compose_pid(pai_type, pai_number, i)
          if i == key_cid && @type != :ankan
            @taken_pid = pid
          else
            @consumed_pids.push(pid)
          end
        end
      end

      def parse_kakan
        taken_cid = read_bits(2)
        read_bits(2)
        pattern = read_bits(7)
        pai_kind = pattern / 3
        taken_pos = pattern % 3
        pai_type = pai_kind / 9
        pai_number = pai_kind % 9 + 1
        @type = :kakan
        @target_dir = 0
        @consumed_pids = []
        (0...4).each do |i|
          pid = compose_pid(pai_type, pai_number, i)
          if i == taken_cid
            @taken_pid = pid
          else
            @consumed_pids.push(pid)
          end
        end
      end

      def read_bits(num_bits)
        mask = (1 << num_bits) - 1
        result = @num & mask
        @num >>= num_bits
        result
      end
    end

    include(Util)

    def initialize(path)
      super()
      @path = path
      Zlib::GzipReader.open(path) do |f|
        @xml = f.read.force_encoding('utf-8')
      end
    end

    attr_reader :path, :xml

    def play
      @doc = Nokogiri.XML(@xml)
      elems = @doc.root.children
      elems.each_with_index do |elem, j|
        if on_tenhou_event(elem, elems[j + 1]) == :broken
          raise('Something is wrong')
          break  # Something is wrong.
        end
      rescue StandardError
        warn('While interpreting element: %s' % elem)
        raise
      end
    end
  end
end
