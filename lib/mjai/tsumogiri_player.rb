# frozen_string_literal: true

require 'mjai/player'

module Mjai
  class TsumogiriPlayer < Player
    def respond_to_action(action)
      case action.type
      when :tsumo, :chi, :pon
        return create_action({ type: :dahai, pai: tehais[-1], tsumogiri: true }) if action.actor == self
      end
      nil
    end
  end
end
