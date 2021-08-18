# frozen_string_literal: true

module Mjai
  class Pai
    include(Comparable)

    TSUPAI_STRS = ' ESWNPFC'.split(//)

    def self.parse_pais(str)
      type = nil
      pais = []
      red = false
      str.gsub(/\s+/, '').split(//).reverse_each do |ch|
        next if ch =~ /^\s$/

        if ch =~ /^[mps]$/
          type = ch
        elsif ch =~ /^[1-9]$/
          raise(ArgumentError, 'type required after number') unless type

          pais.push(Pai.new(type, ch.to_i, red))
          red = false
        elsif TSUPAI_STRS.include?(ch)
          pais.push(Pai.new(ch))
        elsif ch == 'r'
          red = true
        else
          raise(ArgumentError, 'unexpected character: %s', ch)
        end
      end
      pais.reverse
    end

    def self.dump_pais(pais)
      pais.map { |pai| '%-3s' % pai }.join('')
    end

    def initialize(*args)
      case args.size
      when 1
        str = args[0]
        if str == '?'
          @type = @number = nil
          @red = false
        elsif str =~ /\A([1-9])([mps])(r)?\z/
          @type = Regexp.last_match(2)
          @number = Regexp.last_match(1).to_i
          @red = !Regexp.last_match(3).nil?
        elsif number = TSUPAI_STRS.index(str)
          @type = 't'
          @number = number
          @red = false
        else
          raise(ArgumentError, 'Unknown pai string: %s' % str)
        end
      when 2, 3
        (@type, @number, @red) = args
        @red = false if @red.nil?
      else
        raise(ArgumentError, 'Wrong number of args.')
      end
      if !@type.nil? || !@number.nil?
        raise(format('Bad type: %p', @type)) unless %w[m p s t].include?(@type)
        raise(format('number must be Integer: %p', @number)) unless @number.is_a?(Integer)
        raise(format('red must be boolean: %p', @red)) if @red != true && @red != false
      end
    end

    def to_s
      if !@type
        '?'
      elsif @type == 't'
        TSUPAI_STRS[@number]
      else
        format('%d%s%s', @number, @type, @red ? 'r' : '')
      end
    end

    def inspect
      'Pai[%s]' % to_s
    end

    attr_reader(:type, :number)

    def valid?
      if @type.nil? && @number.nil?
        true
      elsif @type == 't'
        (1..7).include?(@number)
      else
        (1..9).include?(@number)
      end
    end

    def red?
      @red
    end

    def yaochu?
      @type == 't' || @number == 1 || @number == 9
    end

    def fonpai?
      @type == 't' && (1..4).include?(@number)
    end

    def sangenpai?
      @type == 't' && (5..7).include?(@number)
    end

    def next(n)
      Pai.new(@type, @number + n)
    end

    def data
      [@type || '', @number || -1, @red ? 1 : 0]
    end

    def ==(other)
      self.class == other.class && data == other.data
    end

    alias eql? ==

    def hash
      data.hash
    end

    def <=>(other)
      if instance_of?(other.class)
        data <=> other.data
      else
        raise(ArgumentError, 'invalid comparison')
      end
    end

    def remove_red
      Pai.new(@type, @number)
    end

    def same_symbol?(other)
      @type == other.type && @number == other.number
    end

    # Next pai in terms of dora derivation.
    def succ
      number = if (@type == 't' && @number == 4) || (@type != 't' && @number == 9)
                 1
               elsif @type == 't' && @number == 7
                 5
               else
                 @number + 1
               end
      Pai.new(@type, number)
    end

    UNKNOWN = Pai.new(nil, nil)
  end
end
