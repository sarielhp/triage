# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'json'
require 'digest'
require 'open3'

ROOT = File.expand_path('..', __dir__)

def run!(*args)
  puts args.join(' ')
  system(*args) || raise("command failed: #{args.first}")
end

def median(values)
  sorted = values.sort
  (sorted[(sorted.length - 1) / 2] + sorted[sorted.length / 2]) / 2
end

def summarize(paths, destination)
  CSV.open(File.join(destination, 'summary.csv'), 'w') do |out|
    out << %w[corpus method median_ms min_ms max_ms]
    paths.each do |label, path|
      CSV.read(path, headers: true).group_by { |r| r['method'] }.each do |method, rows|
        times = rows.map { |r| Float(r['seconds_per_corpus']) * 1000 }
        out << [label, method, median(times), times.min, times.max]
      end
    end
  end
end

def metadata(inputs)
  revision, = Open3.capture2('git', '-C', ROOT, 'rev-parse', 'HEAD')
  julia, = Open3.capture2('julia', '--version')
  compiler, = Open3.capture2(ENV.fetch('CXX', 'c++'), '--version')
  cpu, = Open3.capture2('uname', '-srmo')
  { utc: Time.now.utc.to_s, revision: revision.strip, julia: julia.strip,
    compiler: compiler.lines.first&.strip, system: cpu.strip,
    affinity_cpu: ENV.fetch('TRIAGE_CPU', nil),
    inputs: inputs.to_h { |p| [File.basename(p), Digest::SHA256.file(p).hexdigest] },
    sources: Dir.glob(File.join(ROOT, '{include,julia/src,bench,tests,scripts}/**/*'))
                .select { |p| File.file?(p) }
                .to_h { |p| [p.delete_prefix("#{ROOT}/"), Digest::SHA256.file(p).hexdigest] } }
end

status = ARGV.delete('--status')
strategies = ARGV.delete('--strategies')
triage_only = ARGV.delete('--triage-only')
abort 'choose only one timing mode' if [status, strategies, triage_only].compact.length > 1
strategies ||= triage_only
abort 'usage: time_corpora.rb BUILD INPUTS OUTPUT [--strategies|--triage-only|--status]' unless ARGV.length == 3
build, inputs, output = ARGV.map { |path| File.expand_path(path) }
FileUtils.mkdir_p(output)
paths = Dir.glob(File.join(inputs, '*.bin'))
raise 'no input corpora' if paths.empty?

prefix = ENV.key?('TRIAGE_CPU') ? ['taskset', '-c', ENV.fetch('TRIAGE_CPU')] : []
File.write(File.join(output, 'environment.json'), JSON.pretty_generate(metadata(paths)))
measurements = []
action = strategies ? 'bench-strategies' : 'bench'
action = 'bench-status' if status
cpp_action = triage_only ? 'bench-triage' : action
paths.each do |input|
  label = File.basename(input, '.bin')
  cpp = File.join(output, "#{label}-cpp.csv")
  julia = File.join(output, "#{label}-julia.csv")
  run!(*prefix, File.join(build, 'triage_bench'), cpp_action, input, cpp)
  run!(*prefix, 'julia', File.join(ROOT, 'scripts/julia_corpus.jl'), action, input, julia)
  measurements.push([label, cpp], [label, julia])
end
summarize(measurements, output)
