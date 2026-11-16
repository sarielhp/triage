# frozen_string_literal: true

require 'fileutils'
require 'digest'

ROOT = File.expand_path('..', __dir__)

def run!(*args)
  puts args.join(' ')
  system(*args) || raise("command failed: #{args.first}")
end

bounded = ARGV.delete('--bounded')
array = ARGV.delete('--array')
abort 'choose only one mesh mode' if bounded && array
abort 'usage: check_corpora.rb BUILD INPUTS OUTPUT [--bounded|--array]' unless ARGV.length == 3
build, inputs, output = ARGV.map { |path| File.expand_path(path) }
FileUtils.mkdir_p(output)
executable = File.join(build, 'triage_bench')
action = bounded ? 'dump-bounded' : 'dump'
action = 'dump-array' if array
Dir.glob(File.join(inputs, '*.bin')).each do |input|
  label = File.basename(input, '.bin')
  cpp = File.join(output, "#{label}-cpp.bin")
  julia = File.join(output, "#{label}-julia.bin")
  run!(executable, action, input, cpp)
  run!('julia', File.join(ROOT, 'scripts/julia_corpus.jl'), action, input, julia)
  raise "C++/Julia disagreement: #{label}" unless Digest::SHA256.file(cpp) == Digest::SHA256.file(julia)

  # Independent exact arithmetic checks every triangle and boundary edge.
  run!('julia', File.join(ROOT, 'scripts/julia_corpus.jl'), 'validate', input, cpp)
  puts "PASS #{label}: C++/Julia byte-identical; no added vertices"
end
