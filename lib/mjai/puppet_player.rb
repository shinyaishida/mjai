# frozen_string_literal: true

require 'mjai/player'

module Mjai
  class PuppetPlayer < Player
    def respond_to_action(_action)
      nil
    end
  end
end
