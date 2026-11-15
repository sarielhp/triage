# frozen_string_literal: true

# Quick: generated tests. Full: download, prepare, certify, time all tile and
# synthetic corpora. Geography adds the pinned GSHHG/Census boundary archives.
require 'fileutils'
require_relative 'tmp_space'

ROOT = File.expand_path('..', __dir__)
ProjectTmp.project = 'triage'

def run!(*args)
  puts args.join(' ')
  system(*args) || raise("command failed: #{args.first}")
end

def julia_script(name, *args)
  run!('julia', File.join(ROOT, 'scripts', name), *args)
end

def geography(work, downloads, inputs, records)
  run!('ruby', File.join(ROOT, 'scripts/geographic/extract.rb'), downloads, records)
  raw = File.join(work, 'geographic-raw.bin')
  run!('ruby', File.join(ROOT, 'scripts/extract_hole_geography.rb'), downloads, raw,
       File.join(records, 'geographic-hole-sources.csv'))
  julia_script('prepare_geography.jl', downloads, inputs, records)
  julia_script('prepare_hole_geography.jl', raw, inputs, records)
end

def full_run(work, build, with_geography, sanitize)
  downloads, inputs, records = %w[downloads inputs records].map { |n| File.join(work, n) }
  options = with_geography ? ['--geography'] : []
  run!('ruby', File.join(ROOT, 'scripts/download.rb'), downloads, *options)
  julia_script('prepare_all.jl', File.join(downloads, 'earcut-js'), inputs, records)
  geography(work, downloads, inputs, records) if with_geography
  run!(File.join(build, 'triage_test'), *Dir.glob(File.join(inputs, '*.bin')))
  run!('ruby', File.join(ROOT, 'scripts/check_corpora.rb'), build, inputs, File.join(work, 'meshes'))
  return if sanitize # Instrumented runs check correctness, never performance.

  run!('ruby', File.join(ROOT, 'scripts/time_corpora.rb'), build, inputs, File.join(work, 'timings'))
end

unknown = ARGV - %w[--full --geography --sanitize]
abort "unknown options: #{unknown.join(' ')}" unless unknown.empty?

work = ProjectTmp.mktmpdir('verification')
puts "Artifacts: #{work} (copy wanted results before the 24-hour temporary cleanup)"
ENV['TMPDIR'] = File.join(work, 'tmp')
FileUtils.mkdir_p(ENV.fetch('TMPDIR', nil))
build = File.join(work, 'build')
options = ARGV.include?('--sanitize') ? ['-DTRIAGE_SANITIZERS=ON'] : []
run!('cmake', '-S', ROOT, '-B', build, '-DCMAKE_BUILD_TYPE=Release', *options)
run!('cmake', '--build', build, '--parallel', '2')
run!('ctest', '--test-dir', build, '--output-on-failure')
run!('julia', "--project=#{File.join(ROOT, 'julia')}", File.join(ROOT, 'julia/test/runtests.jl'))
full_run(work, build, ARGV.include?('--geography'), ARGV.include?('--sanitize')) if ARGV.include?('--full')
puts "PASS; artifacts retained at #{work}"
