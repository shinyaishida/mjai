# frozen_string_literal: true

require 'ostruct'

require 'mjai/pai'
require 'mjai/tenpai_analysis'

module Mjai
  class Player
    attr_reader :id,
                :tehais,          # 手牌
                :furos,           # 副露
                :ho,              # 河 (鳴かれた牌を含まない)
                :sutehais,        # 捨牌 (鳴かれた牌を含む)
                :extra_anpais,    # sutehais以外のこのプレーヤに対する安牌
                :reach_state,
                :reach_ho_index,
                :pao_for_id,
                :attributes
    attr_accessor :name, :game, :score

    def anpais
      @sutehais + @extra_anpais
    end

    def reach?
      @reach_state == :accepted
    end

    def double_reach?
      @double_reach
    end

    def ippatsu_chance?
      @ippatsu_chance
    end

    def rinshan?
      @rinshan
    end

    def update_state(action)
      if @game.previous_action &&
         %i[dahai kakan].include?(@game.previous_action.type) &&
         @game.previous_action.actor != self &&
         action.type != :hora
        @extra_anpais.push(@game.previous_action.pai)
      end

      case action.type
      when :start_game
        @id = action.id
        @name = action.names[@id] if action.names
        @score = 25_000
        @attributes = OpenStruct.new
        @tehais = nil
        @furos = nil
        @ho = nil
        @sutehais = nil
        @extra_anpais = nil
        @reach_state = nil
        @reach_ho_index = nil
        @double_reach = false
        @ippatsu_chance = false
        @pao_for_id = nil
        @rinshan = false
      when :start_kyoku
        @tehais = action.tehais[id]
        @furos = []
        @ho = []
        @sutehais = []
        @extra_anpais = []
        @reach_state = :none
        @reach_ho_index = nil
        @double_reach = false
        @ippatsu_chance = false
        @pao_for_id = nil
        @rinshan = false
      when :chi, :pon, :daiminkan, :ankan
        @ippatsu_chance = false
      when :tsumo
        # - 純正巡消しは発声＆和了打診後（加槓のみ)、嶺上ツモの前（連続する加槓の２回目には一発は付かない）
        if @game.previous_action &&
           @game.previous_action.type == :kakan
          @ippatsu_chance = false
        end
      end

      if action.actor == self
        case action.type
        when :tsumo
          @tehais.sort!
          @tehais.push(action.pai)
        when :dahai
          delete_tehai(action.pai)
          @tehais.sort!
          @ho.push(action.pai)
          @sutehais.push(action.pai)
          @ippatsu_chance = false
          @rinshan = false
          @extra_anpais.clear unless reach?
        when :chi, :pon, :daiminkan, :ankan
          action.consumed.each do |pai|
            delete_tehai(pai)
          end
          @furos.push(Furo.new({
                                 type: action.type,
                                 taken: action.pai,
                                 consumed: action.consumed,
                                 target: action.target
                               }))
          @rinshan = true if %i[daiminkan ankan].include?(action.type)

          # 包
          if %i[daiminkan pon].include?(action.type) && ((action.pai.sangenpai? && @furos.select do |f|
                                                            f.pais[0].sangenpai?
                                                          end.size == 3) ||
               (action.pai.fonpai? && @furos.select { |f| f.pais[0].fonpai? }.size == 4))
            @pao_for_id = action.target.id
          end
        when :kakan
          delete_tehai(action.pai)
          pon_index =
            @furos.index { |f| f.type == :pon && f.taken.same_symbol?(action.pai) }
          raise('should not happen') unless pon_index

          @furos[pon_index] = Furo.new({
                                         type: :kakan,
                                         taken: @furos[pon_index].taken,
                                         consumed: @furos[pon_index].consumed + [action.pai],
                                         target: @furos[pon_index].target
                                       })
          @rinshan = true
        when :reach
          @reach_state = :declared
          @double_reach = true if @game.first_turn?
        when :reach_accepted
          @reach_state = :accepted
          @reach_ho_index = @ho.size - 1
          @ippatsu_chance = true
        end
      end

      if action.target == self
        case action.type
        when :chi, :pon, :daiminkan
          pai = @ho.pop
          raise('should not happen') if pai != action.pai
        end
      end

      @score = action.scores[id] if action.scores
    end

    def jikaze
      Pai.new('t', 1 + (4 + @id - @game.oya.id) % 4) if @game.oya
    end

    def tenpai?
      ShantenAnalysis.new(@tehais, 0).shanten <= 0
    end

    def furiten?
      return false if @tehais.size % 3 != 1
      return false if @tehais.include?(Pai::UNKNOWN)

      tenpai_info = TenpaiAnalysis.new(@tehais)
      return false unless tenpai_info.tenpai?

      anpais = self.anpais
      tenpai_info.waited_pais.any? { |pai| anpais.include?(pai) }
    end

    def can_reach?(shanten_analysis = nil)
      shanten_analysis ||= ShantenAnalysis.new(@tehais, 0)
      @game.current_action.type == :tsumo &&
        @game.current_action.actor == self &&
        shanten_analysis.shanten <= 0 &&
        @furos.all? { |f| f.type == :ankan } &&
        !reach? &&
        game.num_pipais >= 4 &&
        @score >= 1000
    end

    def can_hora?(shanten_analysis = nil)
      action = @game.current_action
      if action.type == :tsumo && action.actor == self
        hora_type = :tsumo
        pais = @tehais
      elsif %i[dahai kakan].include?(action.type) && action.actor != self
        hora_type = :ron
        pais = @tehais + [action.pai]
      else
        return false
      end
      shanten_analysis ||= ShantenAnalysis.new(pais, -1)
      hora_action =
        create_action({ type: :hora, target: action.actor, pai: pais[-1] })
      shanten_analysis.shanten == -1 &&
        @game.get_hora(hora_action, { previous_action: action }).valid? &&
        (hora_type == :tsumo || !furiten?)
    end

    def can_ryukyoku?
      @game.current_action.type == :tsumo &&
        @game.current_action.actor == self &&
        @game.first_turn? &&
        @tehais.select(&:yaochu?).uniq.size >= 9
    end

    # Possible actions except for dahai.
    def possible_actions
      action = @game.current_action
      result = []
      if (action.type == :tsumo && action.actor == self) ||
         (%i[dahai kakan].include?(action.type) && action.actor != self)
        if can_hora?
          result.push(create_action({
                                      type: :hora,
                                      target: action.actor,
                                      pai: action.pai
                                    }))
        end
        result.push(create_action({ type: :reach })) if can_reach?
        result.push(create_action({ type: :ryukyoku, reason: :kyushukyuhai })) if can_ryukyoku?
      end
      result += possible_furo_actions
      result
    end

    def possible_furo_actions
      action = @game.current_action
      result = []

      if action.type == :dahai &&
         action.actor != self &&
         !reach? &&
         @game.num_pipais.positive?

        if @game.can_kan?
          get_pais_combinations([action.pai] * 3, @tehais).each do |consumed|
            result.push(create_action({
                                        type: :daiminkan,
                                        pai: action.pai,
                                        consumed: consumed,
                                        target: action.actor
                                      }))
          end
        end
        get_pais_combinations([action.pai] * 2, @tehais).each do |consumed|
          result.push(create_action({
                                      type: :pon,
                                      pai: action.pai,
                                      consumed: consumed,
                                      target: action.actor
                                    }))
        end
        if (action.actor.id + 1) % 4 == id && action.pai.type != 't'
          (0...3).each do |i|
            target_pais = ((-i...(-i + 3)).to_a - [0]).map do |j|
              Pai.new(action.pai.type, action.pai.number + j)
            end
            get_pais_combinations(target_pais, @tehais).each do |consumed|
              result.push(create_action({
                                          type: :chi,
                                          pai: action.pai,
                                          consumed: consumed,
                                          target: action.actor
                                        }))
            end
          end
        end
        # Excludes furos which forces kuikae afterwards.
        result = result.select do |a|
          a.type == :daiminkan || !possible_dahais_after_furo(a).empty?
        end

      elsif action.type == :tsumo &&
            action.actor == self &&
            @game.num_pipais.positive? &&
            @game.can_kan?

        tehais.uniq.each do |pai|
          same_pais = tehais.select { |tp| tp.same_symbol?(pai) }
          if same_pais.size >= 4 && !pai.red?
            if reach?
              orig_tenpai = TenpaiAnalysis.new(tehais[0...-1])
              new_tenpai = TenpaiAnalysis.new(
                tehais.reject { |tp| tp.same_symbol?(pai) }
              )
              ok = new_tenpai.tenpai? && new_tenpai.waited_pais == orig_tenpai.waited_pais
            else
              ok = true
            end
            result.push(create_action({ type: :ankan, consumed: same_pais })) if ok
          end
          pon = furos.find { |f| f.type == :pon && f.taken.same_symbol?(pai) }
          result.push(create_action({ type: :kakan, pai: pai, consumed: pon.pais })) if pon
        end

      end

      result
    end

    def get_pais_combinations(target_pais, source_pais)
      return Set.new([[]]) if target_pais.empty?

      result = Set.new
      source_pais.select { |pai| target_pais[0].same_symbol?(pai) }.uniq.each do |pai|
        new_source_pais = source_pais.dup
        new_source_pais.delete_at(new_source_pais.index(pai))
        get_pais_combinations(target_pais[1..], new_source_pais).each do |cdr_pais|
          result.add(([pai] + cdr_pais).sort)
        end
      end
      result
    end

    def possible_dahais(action = @game.current_action, tehais = @tehais)
      if reach? && action.type == :tsumo && action.actor == self

        # Only tsumogiri is allowed after reach.
        [action.pai]

      elsif action.type == :reach

        # Tehais after the dahai must be tenpai just after reach.
        result = []
        tehais.uniq.each do |pai|
          pais = tehais.dup
          pais.delete_at(pais.index(pai))
          result.push(pai) if ShantenAnalysis.new(pais, 0).shanten <= 0
        end
        result

      else

        # Excludes kuikae.
        tehais.uniq - kuikae_dahais(action, tehais)

      end
    end

    def kuikae_dahais(action = @game.current_action, tehais = @tehais)
      consumed = action.consumed ? action.consumed.sort : nil
      forbidden_rnums = if action.type == :chi && action.actor == self
                          if consumed[1].number == consumed[0].number + 1
                            [-1, 2]
                          else
                            [1]
                          end
                        elsif action.type == :pon && action.actor == self
                          [0]
                        else
                          []
                        end
      if forbidden_rnums.empty?
        []
      else
        key_pai = consumed[0]
        tehais.uniq.select do |pai|
          pai.type == key_pai.type &&
            forbidden_rnums.any? { |rn| key_pai.number + rn == pai.number }
        end
      end
    end

    def possible_dahais_after_furo(action)
      remains = @tehais.dup
      action.consumed.each do |pai|
        remains.delete_at(remains.index(pai))
      end
      possible_dahais(action, remains)
    end

    def context
      Context.new({
                    oya: self == game.oya,
                    bakaze: game.bakaze,
                    jikaze: jikaze,
                    doras: game.doras,
                    uradoras: [], # TODO
                    reach: reach?,
                    double_reach: false, # TODO
                    ippatsu: false,  # TODO
                    rinshan: false,  # TODO
                    haitei: game.num_pipais.zero?,
                    first_turn: false, # TODO
                    chankan: false  # TODO
                  })
    end

    def delete_tehai(pai)
      pai_index = @tehais.index(pai) || @tehais.index(Pai::UNKNOWN)
      raise("trying to delete #{pai} which is not in tehais: #{@tehais}") unless pai_index

      @tehais.delete_at(pai_index)
    end

    def create_action(params = {})
      Action.new({ actor: self }.merge(params))
    end

    def rank
      @game.ranked_players.index(self) + 1
    end

    def inspect
      "\#<#{self.class}:#{@id}>"
    end

    private

    def reset; end
  end
end
