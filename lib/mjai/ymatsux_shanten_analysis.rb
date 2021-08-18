# frozen_string_literal: true

require 'mjai/pai'
require 'mjai/mentsu'

module Mjai
  class YmatsuxShantenAnalysis
    NUM_PIDS = 9 * 3 + 7
    TYPES = %w[m p s t].freeze
    TYPE_TO_TYPE_ID = { 'm' => 0, 'p' => 1, 's' => 2, 't' => 3 }.freeze

    def self.create_mentsus
      mentsus = []
      (0...NUM_PIDS).each do |i|
        mentsus.push([i] * 3)
      end
      (0...3).each do |t|
        (0...7).each do |n|
          pid = t * 9 + n
          mentsus.push([pid, pid + 1, pid + 2])
        end
      end
      mentsus
    end

    MENTSUS = create_mentsus

    def initialize(pais)
      @pais = pais
      count_vector = YmatsuxShantenAnalysis.pais_to_count_vector(pais)
      @shanten = YmatsuxShantenAnalysis.calculate_shantensu_internal(count_vector, [0] * NUM_PIDS, 4, 0, 1.0 / 0.0)
    end

    attr_reader(:pais, :shanten)

    def self.pais_to_count_vector(pais)
      count_vector = [0] * NUM_PIDS
      pais.each do |pai|
        count_vector[pai_to_pid(pai)] += 1
      end
      count_vector
    end

    def self.pai_to_pid(pai)
      TYPE_TO_TYPE_ID[pai.type] * 9 + (pai.number - 1)
    end

    def self.pid_to_pai(pid)
      Pai.new(TYPES[pid / 9], pid % 9 + 1)
    end

    def self.calculate_shantensu_internal(
      current_vector, target_vector, left_mentsu, min_mentsu_id, found_min_shantensu
    )
      min_shantensu = found_min_shantensu
      if left_mentsu.zero?
        (0...NUM_PIDS).each do |pid|
          target_vector[pid] += 2
          if valid_target_vector?(target_vector)
            shantensu = calculate_shantensu_lowerbound(current_vector, target_vector)
            min_shantensu = [shantensu, min_shantensu].min
          end
          target_vector[pid] -= 2
        end
      else
        (min_mentsu_id...MENTSUS.size).each do |mentsu_id|
          add_mentsu(target_vector, mentsu_id)
          lower_bound = calculate_shantensu_lowerbound(current_vector, target_vector)
          if valid_target_vector?(target_vector) && lower_bound < found_min_shantensu
            shantensu = calculate_shantensu_internal(
              current_vector, target_vector, left_mentsu - 1, mentsu_id, min_shantensu
            )
            min_shantensu = [shantensu, min_shantensu].min
          end
          remove_mentsu(target_vector, mentsu_id)
        end
      end
      min_shantensu
    end

    def self.calculate_shantensu_lowerbound(current_vector, target_vector)
      count = (0...NUM_PIDS).inject(0) do |c, pid|
        c + (target_vector[pid] > current_vector[pid] ? target_vector[pid] - current_vector[pid] : 0)
      end
      count - 1
    end

    def self.valid_target_vector?(target_vector)
      target_vector.all? { |c| c <= 4 }
    end

    def self.add_mentsu(target_vector, mentsu_id)
      MENTSUS[mentsu_id].each do |pid|
        target_vector[pid] += 1
      end
    end

    def self.remove_mentsu(target_vector, mentsu_id)
      MENTSUS[mentsu_id].each do |pid|
        target_vector[pid] -= 1
      end
    end
  end
end
