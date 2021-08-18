# frozen_string_literal: true

require 'mjai/archive'
require 'mjai/puppet_player'
require 'mjai/action'

module Mjai
  class MjsonArchive < Archive
    def initialize(path)
      super()
      @path = path
      @raw_actions = []
      File.foreach(@path) do |line|
        @raw_actions.push(Action.from_json(line.chomp, self))
      end
    end

    attr_reader(:path, :raw_actions)

    def play
      @raw_actions.each do |action|
        do_action(action)
      end
    end
  end
end
