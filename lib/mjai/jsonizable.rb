# frozen_string_literal: true

require 'rubygems'
require 'json'

require 'mjai/pai'

module Mjai
  class JSONizable
    def self.define_fields(specs)
      @@field_specs = specs
      @@field_specs.each do |name, _type|
        define_method(name) do
          return @fields[name]
        end
      end
    end

    def self.from_json(json, game)
      plain = JSON.parse(json)
      begin
        from_plain(plain, nil, game)
      rescue ValidationError => e
        raise(ValidationError, "#{e.message} JSON: #{json}")
      end
    end

    def self.from_plain(plain, name, game)
      validate(plain.is_a?(Hash), "#{name || 'The response'} must be an object.")
      fields = {}
      @@field_specs.each do |field_name, type|
        field_plain = plain[field_name.to_s]
        next if field_plain.nil?

        fields[field_name] = plain_to_obj(
          field_plain, type, name ? "#{name}.#{field_name}" : field_name.to_s, game
        )
      end
      new(fields)
    end

    def self.plain_to_obj(plain, type, name, game)
      case type
      when :number
        validate_class(plain, Integer, name)
        plain
      when :string
        validate_class(plain, String, name)
        plain
      when :string_or_null
        validate(plain.is_a?(String) || plain.nil?, "#{name} must be String or null.")
        plain
      when :boolean
        validate(
          plain.is_a?(TrueClass) || plain.is_a?(FalseClass),
          "#{name} must be either true or false."
        )
        plain
      when :symbol
        validate_class(plain, String, name)
        validate(!plain.empty?, "#{name} must not be empty.")
        plain.intern
      when :player
        validate_class(plain, Integer, name)
        validate((0...4).include?(plain), "#{name} must be either 0, 1, 2 or 3.")
        game.players[plain]
      when :pai
        validate_class(plain, String, name)
        begin
          Pai.new(plain)
        rescue ArgumentError => e
          raise(ValidationError, "Error in #{name}: #{e.message}")
        end
      when :yaku
        validate_class(plain, Array, name)
        validate(
          plain.size == 2 && plain[0].is_a?(String) && plain[1].is_a?(Integer),
          "#{name} must be an array of [String, Integer]."
        )
        validate(!plain[0].empty?, "#{name}[0] must not be empty.")
        [plain[0].intern, plain[1]]
      when :action
        from_plain(plain, name, game)
      when :numbers
        plains_to_objs(plain, :number, name, game)
      when :strings
        plains_to_objs(plain, :string, name, game)
      when :strings_or_nulls
        plains_to_objs(plain, :string_or_null, name, game)
      when :booleans
        plains_to_objs(plain, :boolean, name, game)
      when :symbols
        plains_to_objs(plain, :symbol, name, game)
      when :pais
        plains_to_objs(plain, :pai, name, game)
      when :pais_list
        plains_to_objs(plain, :pais, name, game)
      when :yakus
        plains_to_objs(plain, :yaku, name, game)
      when :actions
        plains_to_objs(plain, :action, name, game)
      else
        raise('unknown type')
      end
    end

    def self.plains_to_objs(plains, type, name, game)
      validate_class(plains, Array, name)
      plains.each_with_index.map do |c, i|
        plain_to_obj(c, type, "#{name}[#{i}]", game)
      end
    end

    def self.validate(criterion, message)
      raise(ValidationError, message) unless criterion
    end

    def self.validate_class(plain, klass, name)
      validate(plain.is_a?(klass), "#{name} must be #{klass}.")
    end

    def initialize(fields)
      fields.each do |name, _value|
        raise(ArgumentError, 'unknown field: %p' % name) if @@field_specs.none? { |n, _t| n == name }
      end
      @fields = fields
    end

    attr_reader(:fields)

    def to_json(*_args)
      JSON.dump(to_plain)
    end

    def to_plain
      hash = {}
      @@field_specs.each do |name, type|
        obj = @fields[name]
        next if obj.nil?

        case type
        when :symbol, :pai
          plain = obj.to_s
        when :player
          plain = obj.id
        when :symbols, :pais
          plain = obj.map(&:to_s)
        when :pais_list
          plain = obj.map { |o| o.map(&:to_s) }
        when :yakus
          plain = obj.map { |s, n| [s.to_s, n] }
        when :actions
          plain = obj.map(&:to_plain)
        when :number, :numbers, :string, :strings, :string_or_null, :strings_or_nulls, :boolean, :booleans
          plain = obj
        else
          raise('unknown type')
        end
        hash[name.to_s] = plain
      end
      hash
    end

    alias to_s to_json

    def merge(hash)
      fields = @fields.dup
      hash.each do |name, value|
        raise(ArgumentError, 'unknown field: %p' % k) if @@field_specs.none? { |n, _t| n == name }

        if value.nil?
          fields.delete(name)
        else
          fields[name] = value
        end
      end
      self.class.new(fields)
    end

    def ==(other)
      self.class == other.class && @fields == other.fields
    end

    alias eql? ==

    def hash
      @fields.hash
    end
  end
end
