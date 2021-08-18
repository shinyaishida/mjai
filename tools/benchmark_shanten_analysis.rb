# frozen_string_literal: true

$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/../lib")

require 'mjai/shanten_analysis'
require 'mjai/ymatsux_shanten_analysis'
require 'mjai/archive'

include(Mjai)

def get_shanten(pais, class_name)
  case class_name
  when 'ShantenAnalysis'
    ShantenAnalysis.new(pais, nil, [:normal], pais.size, false).shanten
  when 'YmatsuxShantenAnalysis'
    YmatsuxShantenAnalysis.new(pais).shanten
  else
    raise('Unknown class name')
  end
end

case ARGV.shift

when 'generate'
  pai_sets = []
  Dir['mjlog/mjlog_pf4-20_n1/*.mjlog'].sort.reverse[0, 100].each do |path|
    archive = Archive.load(path)
    archive.each_action do |action|
      pai_sets.push(action.actor.tehais.dup.sort) if action.type == :tsumo && action.actor.tehais.size == 14
    end
  end
  open('data/shanten_benchmark_data.str.txt', 'w') do |sf|
    open('data/shanten_benchmark_data.num.txt', 'w') do |nf|
      pai_sets.sample(1000).each do |pais|
        shanten = ShantenAnalysis.new(pais, nil, [:normal]).shanten
        sf.puts((pais.map(&:to_s) + [shanten]).join(' '))
        nf.puts((pais.map { |pai| YmatsuxShantenAnalysis.pai_to_pid(pai) } + [shanten]).join(' '))
      end
    end
  end

when 'benchmark_tehai'
  class_name = ARGV.shift
  File.foreach('data/shanten_benchmark_data.str.txt') do |line|
    line = line.chomp
    row = line.split(/ /)
    pais = row[0...-1].map { |s| Pai.new(s) }
    expected_shanten = row[-1].to_i
    actual_shanten = get_shanten(pais, class_name)
    if expected_shanten != actual_shanten
      raise(format('Shanten mismatch: %d != %d for %s', actual_shanten, expected_shanten, line))
    end
  end

when 'benchmark_haipai'
  class_name = ARGV.shift
  srand(0)
  all_pais = (%w[m p s].map { |t| (1..9).map { |n| Pai.new(t, n) } }.flatten +
      (1..7).map { |n| Pai.new('t', n) }) * 4
  pai_sets = (0...100).map { all_pais.sample(14).sort }
  pai_sets.each do |pais|
    get_shanten(pais, class_name)
  end

end
