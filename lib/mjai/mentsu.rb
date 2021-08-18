# frozen_string_literal: true

require 'mjai/with_fields'

module Mjai
  class Mentsu
    extend(WithFields)
    include(Comparable)

    # type: :shuntsu, :kotsu, :toitsu, :ryanmen, :kanchan, :penchan, :single
    # visibility: :an, :min
    define_fields(%i[pais type visibility])

    def initialize(fields)
      @fields = fields
    end

    attr_reader(:fields)

    def inspect
      format("\#<%p %p>", self.class, @fields)
    end

    def ==(other)
      self.class == other.class && @fields == other.fields
    end

    alias eql? ==

    def hash
      @fields.hash
    end

    def <=>(other)
      if instance_of?(other.class)
        Mentsu.field_names.map { |s| @fields[s] } <=>
          Mentsu.field_names.map { |s| other.fields[s] }
      else
        raise(ArgumentError, 'invalid comparison')
      end
    end
  end
end
