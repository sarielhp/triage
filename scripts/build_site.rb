# frozen_string_literal: true

require 'csv'
require 'cgi'

ROOT = File.expand_path('..', __dir__)
RESULTS = File.join(ROOT, 'results/2026-11-15')
NAMES = {
  'tiles-single' => 'Single-ring tiles', 'tiles-holes' => 'Holed tiles',
  'geographic-single' => 'Large geographic rings', 'geographic-holes' => 'Geographic domains with holes',
  'fixtures' => 'Accepted named fixtures', 'synthetic-holes' => 'Synthetic holed domains'
}.freeze
ADVERSARIAL = {
  'comb-16384' => ['Comb, no holes', 65_540].freeze,
  'stacked-holes-64' => ['64 stacked holes', 260].freeze,
  'stacked-holes-256' => ['256 stacked holes', 1_028].freeze,
  'stacked-holes-1024' => ['1,024 stacked holes', 4_100].freeze
}.freeze

def benchmark_rows
  measurements = CSV.read(File.join(RESULTS, 'timings/summary.csv'), headers: true).group_by { |r| r['corpus'] }
  counts = CSV.read(File.join(RESULTS, 'records/corpora.csv'), headers: true).to_h { |r| [r['dataset'], r['polygons']] }
  NAMES.map do |key, title|
    times = measurements.fetch(key).to_h { |r| [r['method'], Float(r['median_ms'])] }
    values = %w[triage-cpp julia earcut].map { |name| format('%.3f', times.fetch(name)) }
    cells = [counts.fetch(key), *values].map { |value| "<td>#{CGI.escapeHTML(value)}</td>" }.join
    "<tr><th scope=\"row\">#{CGI.escapeHTML(title)}</th>#{cells}</tr>"
  end.join("\n")
end

def adversarial_rows
  path = File.join(ROOT, 'results/2026-11-15-bounded/adversarial/summary.csv')
  measurements = CSV.read(path, headers: true).group_by { |r| r['corpus'] }
  ADVERSARIAL.map do |key, (title, vertices)|
    times = measurements.fetch(key).to_h { |r| [r['method'], Float(r['median_ms'])] }
    values = %w[triage-cpp triage-bounded-cpp earcut].map { |name| format('%.3f', times.fetch(name)) }
    cells = [vertices, *values].map { |value| "<td>#{CGI.escapeHTML(value.to_s)}</td>" }.join
    "<tr><th scope=\"row\">#{CGI.escapeHTML(title)}</th>#{cells}</tr>"
  end.join("\n")
end

source = File.read(File.join(ROOT, 'site/index.html'))
svg = File.read(File.join(ROOT, 'docs/assets/triage-wordmark.svg'))
page = source.sub('{{WORDMARK}}', svg).sub('{{BENCHMARK_ROWS}}', benchmark_rows)
page = page.sub('{{ADVERSARIAL_ROWS}}', adversarial_rows)
raise 'unresolved site placeholder' if page.include?('{{')

File.write(File.join(ROOT, 'docs/index.html'), page)
File.write(File.join(ROOT, 'docs/.nojekyll'), '')
puts 'Built docs/index.html from the verified mesh and published benchmark CSV.'
