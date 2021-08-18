# frozen_string_literal: true

require 'set'
require 'mjai/pai'
require 'mjai/mentsu'

module Mjai
  class ShantenAnalysis
    # ryanpen = 両面 or 辺搭
    MENTSU_TYPES = %i[kotsu shuntsu toitsu ryanpen kanta single].freeze

    MENTSU_CATEGORIES = {
      kotsu: :complete,
      shuntsu: :complete,
      toitsu: :toitsu,
      ryanpen: :tatsu,
      kanta: :tatsu,
      single: :single
    }.freeze

    MENTSU_SIZES = {
      complete: 3,
      toitsu: 2,
      tatsu: 2,
      single: 1
    }.freeze

    ALL_TYPES = %i[normal chitoitsu kokushimuso].freeze

    def self.benchmark
      all_pais = (%w[m p s].map { |t| (1..9).map { |n| Pai.new(t, n) } }.flatten +
          (1..7).map { |n| Pai.new('t', n) }) * 4
      start_time = Time.now.to_f
      100.times do
        pais = all_pais.sample(14).sort
        p pais.join(' ')
        shanten = ShantenAnalysis.count(pais)
        p shanten
        #             for i in 0...pais.size
        #               remains_pais = pais.dup()
        #               remains_pais.delete_at(i)
        #               if ShantenAnalysis.count(remains_pais) == shanten
        #                 p pais[i]
        #               end
        #             end
        # gets()
      end
      p Time.now.to_f - start_time
    end

    def initialize(pais, max_shanten = nil, types = ALL_TYPES,
                   num_used_pais = pais.size, need_all_combinations = true)

      @pais = pais
      @max_shanten = max_shanten
      @num_used_pais = num_used_pais
      @need_all_combinations = need_all_combinations
      raise(ArgumentError, 'invalid number of pais') if (@num_used_pais % 3).zero?

      @pai_set = Hash.new(0)
      @pais.each do |pai|
        @pai_set[pai.remove_red] += 1
      end

      @cache = {}
      results = []
      results.push(count_normal(@pai_set, [])) if types.include?(:normal)
      results.push(count_chitoi(@pai_set)) if types.include?(:chitoitsu)
      results.push(count_kokushi(@pai_set)) if types.include?(:kokushimuso)

      @shanten = 1.0 / 0.0
      @combinations = []
      results.each do |shanten, combinations|
        next if @max_shanten && shanten > @max_shanten

        if shanten < @shanten
          @shanten = shanten
          @combinations = combinations
        elsif shanten == @shanten
          @combinations += combinations
        end
      end
    end

    attr_reader(:pais, :shanten, :combinations)

    DetailedCombination = Struct.new(:janto, :mentsus)

    def detailed_combinations
      num_required_mentsus = @pais.size / 3
      result = []
      @combinations.map { |ms| ms.map { |m| convert_mentsu(m) } }.each do |mentsus|
        [nil] + (0...mentsus.size).to_a.each do |janto_index|
          t_mentsus = mentsus.dup
          janto = nil
          if janto_index
            next unless %i[toitsu kotsu].include?(mentsus[janto_index].type)

            janto = t_mentsus.delete_at(janto_index)
          end
          current_shanten =
            -1 +
            (janto_index ? 0 : 1) +
            t_mentsus.map { |m| 3 - m.pais.size }
                     .sort[0, num_required_mentsus]
                     .inject(0, :+)
          next if current_shanten != @shanten

          result.push(DetailedCombination.new(janto, t_mentsus))
        end
      end
      result
    end

    def convert_mentsu(mentsu)
      (type, pais) = mentsu
      if type == :ryanpen
        type = if [[1, 2], [8, 9]].include?(pais.map(&:number))
                 :penta
               else
                 :ryanmen
               end
      end
      Mentsu.new({ type: type, pais: pais, visibility: :an })
    end

    def count_chitoi(pai_set)
      num_toitsus = pai_set.select { |_pai, n| n >= 2 }.size
      num_singles = pai_set.select { |_pai, n| n == 1 }.size
      shanten = if num_toitsus == 6 && num_singles.zero?
                  # toitsu * 5 + kotsu * 1 or toitsu * 5 + kantsu * 1
                  1
                else
                  -1 + [7 - num_toitsus, 0].max
                end
      [shanten, [:chitoitsu]]
    end

    def count_kokushi(pai_set)
      yaochus = pai_set.select { |pai, _n| pai.yaochu? }
      has_yaochu_toitsu = yaochus.any? { |_pai, n| n >= 2 }
      [(13 - yaochus.size) - (has_yaochu_toitsu ? 1 : 0), [:kokushimuso]]
    end

    def count_normal(pai_set, mentsus)
      # TODO: 上がり牌を全部自分が持っているケースを考慮
      key = get_key(pai_set, mentsus)
      unless @cache[key]
        if pai_set.empty?
          # p mentsus
          min_shanten = get_min_shanten_for_mentsus(mentsus)
          min_combinations = [mentsus]
        else
          shanten_lowerbound = get_min_shanten_for_mentsus(mentsus) if @max_shanten
          min_shanten = 1.0 / 0.0
          if @max_shanten && shanten_lowerbound > @max_shanten
            min_combinations = []
          else
            first_pai = pai_set.keys.min
            MENTSU_TYPES.each do |type|
              if @max_shanten == -1
                next if %i[ryanpen kanta].include?(type)
                next if mentsus.any? { |t, _ps| t == :toitsu } && type == :toitsu
              end
              (removed_pais, remains_set) = remove(pai_set, type, first_pai)
              next unless remains_set

              (shanten, combinations) =
                count_normal(remains_set, mentsus + [[type, removed_pais]])
              if shanten < min_shanten
                min_shanten = shanten
                min_combinations = combinations
                break if !@need_all_combinations && min_shanten == -1
              elsif shanten == min_shanten && shanten < 1.0 / 0.0
                min_combinations += combinations
              end
            end
          end
        end
        @cache[key] = [min_shanten, min_combinations]
      end
      @cache[key]
    end

    def get_key(pai_set, mentsus)
      [pai_set, Set.new(mentsus)]
    end

    def get_min_shanten_for_mentsus(mentsus)
      mentsu_categories = mentsus.map { |t, _ps| MENTSU_CATEGORIES[t] }
      num_current_pais = mentsu_categories.map { |m| MENTSU_SIZES[m] }.inject(0, :+)
      num_remain_pais = @pais.size - num_current_pais

      min_shantens = []
      if index = mentsu_categories.index(:toitsu)
        # Assumes the 対子 is 雀頭.
        mentsu_categories.delete_at(index)
        min_shantens.push(get_min_shanten_without_janto(mentsu_categories, num_remain_pais))
      else
        # Assumes 雀頭 is missing.
        min_shantens.push(get_min_shanten_without_janto(mentsu_categories, num_remain_pais) + 1)
        if num_remain_pais >= 2
          # Assumes 雀頭 is in remaining pais.
          min_shantens.push(get_min_shanten_without_janto(mentsu_categories, num_remain_pais - 2))
        end
      end
      min_shantens.min
    end

    def get_min_shanten_without_janto(mentsu_categories, num_remain_pais)
      # Assumes remaining pais generates best combinations.
      mentsu_categories += [:complete] * (num_remain_pais / 3)
      case num_remain_pais % 3
      when 1
        mentsu_categories.push(:single)
      when 2
        mentsu_categories.push(:toitsu)
      end

      sizes = mentsu_categories.map { |m| MENTSU_SIZES[m] }.sort_by(&:-@)
      num_required_mentsus = @num_used_pais / 3
      -1 + sizes[0...num_required_mentsus].inject(0) { |r, n| r + (3 - n) }
    end

    def remove(pai_set, type, first_pai)
      case type
      when :kotsu
        removed_pais = [first_pai] * 3
      when :shuntsu
        removed_pais = shuntsu_piece(first_pai, [0, 1, 2])
      when :toitsu
        removed_pais = [first_pai] * 2
      when :ryanpen
        removed_pais = shuntsu_piece(first_pai, [0, 1])
      when :kanta
        removed_pais = shuntsu_piece(first_pai, [0, 2])
      when :single
        removed_pais = [first_pai]
      else
        raise('should not happen')
      end
      return [nil, nil] unless removed_pais

      result_set = pai_set.dup
      removed_pais.each do |pai|
        if (result_set[pai]).positive?
          result_set[pai] -= 1
          result_set.delete(pai) if (result_set[pai]).zero?
        else
          return [nil, nil]
        end
      end
      [removed_pais, result_set]
    end

    def shuntsu_piece(first_pai, relative_numbers)
      if first_pai.type == 't'
        nil
      else
        relative_numbers.map { |i| Pai.new(first_pai.type, first_pai.number + i) }
      end
    end

    def inspect
      "\#<#{self.class} shanten=#{@shanten} pais=<#{@pais.join(' ')}>>"
    end
  end
end
