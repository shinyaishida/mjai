# frozen_string_literal: true

require 'mjai/action'
require 'mjai/pai'
require 'mjai/furo'
require 'mjai/hora'
require 'mjai/validation_error'

module Mjai
  class Game
    def initialize(players = nil)
      self.players = players if players
      @bakaze = nil
      @kyoku_num = nil
      @honba = nil
      @chicha = nil
      @oya = nil
      @dora_markers = nil
      @current_action = nil
      @previous_action = nil
      @num_pipais = nil
      @num_initial_pipais = nil
      @first_turn = false
    end

    attr_reader :players, :all_pais, :bakaze, :oya, :honba, :dora_markers, :current_action, :previous_action, :all_pais, :num_pipais # ドラ表示牌
    attr_accessor(:last) # kari

    def players=(players)
      @players = players
      @players.each do |player|
        puts player.class
        player.game = self
      end
    end

    def on_action(&block)
      @on_action = block
    end

    def on_responses(&block)
      @on_responses = block
    end

    # Executes the action and returns responses for it from players.
    def do_action(action)
      action = Action.new(action) if action.is_a?(Hash)
      update_state(action)

      @on_action&.call(action)

      responses = (0...4).map do |i|
        @players[i].respond_to_action(action_in_view(action, i, true))
      end

      action_with_logs = action.merge({ logs: responses.map { |r| r&.log } })
      responses = responses.map { |r| !r || r.type == :none ? nil : r.merge({ log: nil }) }
      @on_responses&.call(action_with_logs, responses)

      @previous_action = action
      validate_responses(responses, action)
      responses
    end

    # Updates internal state of Game and Player objects by the action.
    def update_state(action)
      @current_action = action
      @actor = action.actor if action.actor

      case action.type
      when :start_game
        # TODO: change this by red config
        pais = (0...4).map do |i|
          %w[m p s].map { |t| (1..9).map { |n| Pai.new(t, n, n == 5 && i.zero?) } } +
            (1..7).map { |n| Pai.new('t', n) }
        end
        @all_pais = pais.flatten.sort
      when :start_kyoku
        @bakaze = action.bakaze
        @kyoku_num = action.kyoku
        @honba = action.honba
        @oya = action.oya
        @chicha ||= @oya
        @dora_markers = [action.dora_marker]
        @num_pipais = @num_initial_pipais = @all_pais.size - 13 * 4 - 14
        @first_turn = true
      when :tsumo
        @num_pipais -= 1
        @first_turn = false if @num_initial_pipais - @num_pipais > 4
      when :chi, :pon, :daiminkan, :kakan, :ankan
        @first_turn = false
      when :dora
        @dora_markers.push(action.dora_marker)
      end

      (0...4).each do |i|
        @players[i].update_state(action_in_view(action, i, false))
      end
    end

    def action_in_view(action, player_id, for_response)
      player = @players[player_id]
      with_response_hint = for_response && expect_response_from?(player)
      case action.type
      when :start_game
        action.merge({ id: player_id })
      when :start_kyoku
        tehais_list = action.tehais.dup
        (0...4).each do |i|
          tehais_list[i] = [Pai::UNKNOWN] * tehais_list[i].size if i != player_id
        end
        action.merge({ tehais: tehais_list })
      when :tsumo
        if action.actor == player
          action.merge({
                         possible_actions: with_response_hint ? player.possible_actions : nil
                       })
        else
          action.merge({ pai: Pai::UNKNOWN })
        end
      when :dahai, :kakan
        if action.actor != player
          action.merge({
                         possible_actions: with_response_hint ? player.possible_actions : nil
                       })
        else
          action
        end
      when :chi, :pon
        if action.actor == player
          action.merge({
                         cannot_dahai: with_response_hint ? player.kuikae_dahais : nil
                       })
        else
          action
        end
      when :reach
        if action.actor == player
          action.merge({
                         cannot_dahai: with_response_hint ? (player.tehais.uniq - player.possible_dahais) : nil
                       })
        else
          action
        end
      else
        action
      end
    end

    def validate_responses(responses, action)
      (0...4).each do |i|
        response = responses[i]
        begin
          raise(ValidationError, 'Invalid actor.') if response && response.actor != @players[i]

          validate_response_type(response, @players[i], action)
          validate_response_content(response, action) if response
        rescue ValidationError => e
          raise(ValidationError,
                format("Error in player %d's response: %s Response: %s", i, e.message, response))
        end
      end
    end

    def validate_response_type(response, player, action)
      raise(ValidationError, response.message) if response && response.type == :error

      is_actor = player == action.actor
      if expect_response_from?(player)
        case action.type
        when :start_game, :start_kyoku, :end_kyoku, :end_game, :error,
              :hora, :ryukyoku, :dora, :reach_accepted
          valid = !response
        when :tsumo
          valid = if is_actor
                    response &&
                      %i[dahai reach ankan kakan hora ryukyoku].include?(response.type)
                  else
                    !response
                  end
        when :dahai
          valid = if is_actor
                    !response
                  else
                    !response || %i[chi pon daiminkan hora].include?(response.type)
                  end
        when :chi, :pon, :reach
          valid = if is_actor
                    response && response.type == :dahai
                  else
                    !response
                  end
        when :ankan, :daiminkan
          # Actor should wait for tsumo.
          valid = !response
        when :kakan
          valid = if is_actor
                    # Actor should wait for tsumo.
                    !response
                  else
                    # hora is for chankan.
                    !response || response.type == :hora
                  end
        when :log
          valid = !response
        else
          raise(ValidationError, "Unknown action type: '#{action.type}'")
        end
      else
        valid = !response
      end
      unless valid
        raise(ValidationError,
              format("Unexpected response type '%s' for %s.", response ? response.type : :none, action))
      end
    end

    def validate_response_content(response, action)
      case response.type

      when :dahai

        validate_fields_exist(response, %i[pai tsumogiri])
        if action.actor.reach?
          # possible_dahais check doesn't subsume this check. Consider karagiri
          # (with tsumogiri=false) after reach.
          validate(response.tsumogiri, 'tsumogiri must be true after reach.')
        end
        validate(
          response.actor.possible_dahais.include?(response.pai),
          'Cannot dahai this pai. The pai is not in the tehais, ' \
            "it's kuikae, or it causes noten reach."
        )

        # Validates that pai and tsumogiri fields are consistent.
        if %i[tsumo reach].include?(action.type)
          if response.tsumogiri
            tsumo_pai = response.actor.tehais[-1]
            validate(
              response.pai == tsumo_pai,
              format('tsumogiri is true but the pai is not tsumo pai: %s != %s', response.pai, tsumo_pai)
            )
          else
            validate(
              response.actor.tehais[0...-1].include?(response.pai),
              'tsumogiri is false but the pai is not in tehais.'
            )
          end
        else  # after furo
          validate(
            !response.tsumogiri,
            'tsumogiri must be false on dahai after furo.'
          )
        end

      when :chi, :pon, :daiminkan, :ankan, :kakan
        case response.type
        when :ankan
          validate_fields_exist(response, [:consumed])
        when :kakan
          validate_fields_exist(response, %i[pai consumed])
        else
          validate_fields_exist(response, %i[target pai consumed])
          validate(
            response.target == action.actor,
            'target must be %d.' % action.actor.id
          )
        end
        valid = response.actor.possible_furo_actions.any? do |a|
          a.type == response.type &&
            a.pai == response.pai &&
            a.consumed.sort == response.consumed.sort
        end
        validate(valid, 'The furo is not allowed.')

      when :reach
        validate(response.actor.can_reach?, 'Cannot reach.')

      when :hora
        validate_fields_exist(response, %i[target pai])
        validate(
          response.target == action.actor,
          'target must be %d.' % action.actor.id
        )
        if response.target == response.actor
          tsumo_pai = response.actor.tehais[-1]
          validate(
            response.pai == tsumo_pai,
            format('pai is not tsumo pai: %s != %s', response.pai, tsumo_pai)
          )
        else
          validate(
            response.pai == action.pai,
            format('pai is not previous dahai: %s != %s', response.pai, action.pai)
          )
        end
        validate(response.actor.can_hora?, 'Cannot hora.')

      when :ryukyoku
        validate_fields_exist(response, [:reason])
        validate(response.reason == :kyushukyuhai, 'reason must be kyushukyuhai.')
        validate(response.actor.can_ryukyoku?, 'Cannot ryukyoku.')

      end
    end

    def validate(criterion, message)
      raise(ValidationError, message) unless criterion
    end

    def validate_fields_exist(response, field_names)
      field_names.each do |name|
        raise(ValidationError, '%s missing.' % name) unless response.fields.key?(name)
      end
    end

    def doras
      @dora_markers ? @dora_markers.map(&:succ) : nil
    end

    def get_hora(action, params = {})
      raise('should not happen') if action.type != :hora

      hora_type = action.actor == action.target ? :tsumo : :ron
      tehais = if hora_type == :tsumo
                 action.actor.tehais[0...-1]
               else
                 action.actor.tehais
               end
      uradoras = (params[:uradora_markers] || []).map(&:succ)
      Hora.new({
                 tehais: tehais,
                 furos: action.actor.furos,
                 taken: action.pai,
                 hora_type: hora_type,
                 oya: action.actor == oya,
                 bakaze: bakaze,
                 jikaze: action.actor.jikaze,
                 doras: doras,
                 uradoras: uradoras,
                 reach: action.actor.reach?,
                 double_reach: action.actor.double_reach?,
                 ippatsu: action.actor.ippatsu_chance?,
                 rinshan: action.actor.rinshan?,
                 haitei: (num_pipais.zero? && !action.actor.rinshan?),
                 first_turn: @first_turn,
                 chankan: params[:previous_action].type == :kakan
               })
    end

    def first_turn?
      @first_turn
    end

    def can_kan?
      @dora_markers.size < 5
    end

    def ranked_players
      @players.sort_by { |pl| [-pl.score, distance(pl, @chicha)] }
    end

    def distance(player1, player2)
      (4 + player1.id - player2.id) % 4
    end

    def dump_action(action, io = $stdout)
      io.puts(action.to_json)
      io.print(render_board)
    end

    def render_board
      result = ''
      result << (format('%s-%d kyoku %d honba  ', @bakaze, @kyoku_num, @honba)) if @bakaze && @kyoku_num && @honba
      result << ('pipai: %d  ' % num_pipais) if num_pipais
      result << ('dora_marker: %s  ' % @dora_markers.join(' ')) if @dora_markers
      result << "\n"
      @players.each_with_index do |player, i|
        next unless player.tehais

        result << (format("%s%s%d%s tehai: %s %s\n", player == @actor ? '*' : ' ', player == @oya ? '{' : '[', i,
                          player == @oya ? '}' : ']', Pai.dump_pais(player.tehais), player.furos.join(' ')))
        ho_str = if player.reach_ho_index
                   "#{Pai.dump_pais(player.ho[0...player.reach_ho_index])}=#{Pai.dump_pais(player.ho[player.reach_ho_index..])}"
                 else
                   Pai.dump_pais(player.ho)
                 end
        result << ("     ho:    %s\n" % ho_str)
      end
      result << ('-' * 80) << "\n"
      result
    end
  end
end
