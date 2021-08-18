# frozen_string_literal: true

require 'mjai/with_fields'
require 'mjai/mentsu'

module Mjai
  # 副露
  class Furo
    extend(WithFields)

    # type: :chi, :pon, :daiminkan, :kakan, :ankan
    define_fields(%i[type taken consumed target])

    FURO_TYPE_TO_MENTSU_TYPE = {
      chi: :shuntsu,
      pon: :kotsu,
      daiminkan: :kantsu,
      kakan: :kantsu,
      ankan: :kantsu
    }.freeze

    def initialize(fields)
      @fields = fields
    end

    def kan?
      FURO_TYPE_TO_MENTSU_TYPE[type] == :kantsu
    end

    def pais
      (taken ? [taken] : []) + consumed
    end

    def to_mentsu
      Mentsu.new({
                   type: FURO_TYPE_TO_MENTSU_TYPE[type],
                   pais: pais,
                   visibility: type == :ankan ? :an : :min
                 })
    end

    def to_s
      if type == :ankan
        '[# %s %s #]' % consumed[0, 2]
      else
        format('[%s(%p)/%s]', taken, target && target.id, consumed.join(' '))
      end
    end

    def inspect
      format("\#<%p %s>", self.class, to_s)
    end
  end
end
