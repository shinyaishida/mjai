# frozen_string_literal: true

require 'mjai/jsonizable'

module Mjai
  class Action < JSONizable
    define_fields([
                    %i[type symbol],
                    %i[reason symbol],
                    %i[actor player],
                    %i[target player],
                    %i[pao player],
                    %i[pai pai],
                    %i[consumed pais],
                    %i[pais pais],
                    %i[tsumogiri boolean],
                    %i[possible_actions actions],
                    %i[cannot_dahai pais],
                    %i[id number],
                    %i[bakaze pai],
                    %i[kyoku number],
                    %i[honba number],
                    %i[kyotaku number],
                    %i[oya player],
                    %i[dora_marker pai],
                    %i[uradora_markers pais],
                    %i[tehais pais_list],
                    %i[uri string],
                    %i[names strings],
                    %i[hora_tehais pais],
                    %i[yakus yakus],
                    %i[fu number],
                    %i[fan number],
                    %i[hora_points number],
                    %i[tenpais booleans],
                    %i[deltas numbers],
                    %i[scores numbers],
                    %i[text string],
                    %i[message string],
                    %i[log string_or_null],
                    %i[logs strings_or_nulls]
                  ])
  end
end
