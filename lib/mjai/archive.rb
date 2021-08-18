# frozen_string_literal: true

require 'mjai/game'

module Mjai
  autoload(:TenhouArchive, 'mjai/tenhou_archive')
  autoload(:MjsonArchive, 'mjai/mjson_archive')

  class Archive < Game
    class UnsupportedArchiveError < StandardError
    end

    def self.load(path)
      case File.extname(path)
      when '.mjlog'
        TenhouArchive.new(path)
      when '.mjson'
        MjsonArchive.new(path)
      else
        raise('unknown format')
      end
    end

    def initialize
      super((0...4).map { PuppetPlayer.new })
      @actions = nil
    end

    def each_action(&block)
      if block
        on_action(&block)
        play
      else
        enum_for(:each_action)
      end
    end

    def actions
      @actions ||= each_action.to_a
    end

    def expect_response_from?(_player)
      false
    end

    def inspect
      format('#<%p:path=%p>', self.class, path)
    end
  end
end
