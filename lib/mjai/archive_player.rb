# frozen_string_literal: true

require 'mjai/player'
require 'mjai/archive'

module Mjai
  class ArchivePlayer < Player
    def initialize(archive_path)
      super()
      @archive = Archive.load(archive_path)
      @action_index = 0
    end

    def update_state(action)
      super(action)
      expected_action = @archive.actions[@action_index]
      if action.type == :start_game
        action = action.merge({ id: nil })
        expected_action = expected_action.merge({ id: nil })
      end
      if action.to_json != expected_action.to_json
        raise(format(
                "live action doesn't match one in archive\n" \
                "actual: %s\n" \
                "expected: %s\n", action, expected_action
              ))
      end
      @action_index += 1
    end

    def respond_to_action(_action)
      next_action = @archive.actions[@action_index]
      if next_action&.actor &&
         next_action.actor.id.zero? &&
         %i[dahai chi pon daiminkan kakan ankan riichi hora].include?(
           next_action.type
         )
        Action.from_json(next_action.to_json, game)
      end
    end
  end
end
