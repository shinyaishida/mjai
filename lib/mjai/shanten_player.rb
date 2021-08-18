# frozen_string_literal: true

require 'mjai/player'
require 'mjai/shanten_analysis'
require 'mjai/pai'

module Mjai
  class ShantenPlayer < Player
    def initialize(params)
      super()
      @use_furo = params[:use_furo]
    end

    def respond_to_action(action)
      puts "is action actor me?  #{action.actor == self}"
      if action.actor == self
        case action.type

        when :tsumo, :chi, :pon, :reach

          current_shanten_analysis = ShantenAnalysis.new(tehais, nil, [:normal])
          current_shanten = current_shanten_analysis.shanten
          if can_hora?(current_shanten_analysis)
            if @use_furo
              return create_action({ type: :dahai, pai: action.pai, tsumogiri: true })
            else
              return create_action({
                                     type: :hora,
                                     target: action.actor,
                                     pai: action.pai
                                   })
            end
          elsif can_reach?(current_shanten_analysis)
            return create_action({ type: :reach })
          elsif reach?
            return create_action({ type: :dahai, pai: action.pai, tsumogiri: true })
          end

          # Ankan, kakan
          furo_actions = possible_furo_actions
          return furo_actions[0] unless furo_actions.empty?

          sutehai_cands = []
          possible_dahais.each do |pai|
            remains = tehais.dup
            remains.delete_at(tehais.index(pai))
            if ShantenAnalysis.new(remains, current_shanten, [:normal]).shanten ==
               current_shanten
              sutehai_cands.push(pai)
            end
          end
          sutehai_cands = possible_dahais if sutehai_cands.empty?
          # log("sutehai_cands = %p" % [sutehai_cands])
          sutehai = sutehai_cands[rand(sutehai_cands.size)]
          tsumogiri = %i[tsumo reach].include?(action.type) && sutehai == tehais[-1]
          return create_action({ type: :dahai, pai: sutehai, tsumogiri: tsumogiri })

        end

      else  # action.actor != self

        case action.type
        when :dahai
          if can_hora?
            if @use_furo
              return nil
            else
              return create_action({
                                     type: :hora,
                                     target: action.actor,
                                     pai: action.pai
                                   })
            end
          elsif @use_furo
            furo_actions = possible_furo_actions
            return furo_actions[0] unless furo_actions.empty?
          end
        end

      end

      nil
    end
  end
end
