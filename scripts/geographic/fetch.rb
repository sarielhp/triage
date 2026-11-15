# frozen_string_literal: true

require 'csv'
require 'digest'
require 'fileutils'

SOURCES = [
  ['gshhg', 'gshhg-bin-2.3.7.zip',
   'https://www.soest.hawaii.edu/pwessel/gshhg/gshhg-bin-2.3.7.zip',
   '28600e8f7a08645aab43079326df6504212ec5ccb2b4bcf3b5f4f12ed60e82bc',
   '2.3.7 (2017-06-15)', 'LGPL-3.0-or-later (bundled LICENSE.TXT)'],
  ['states', 'tl_2026_us_state.zip',
   'https://www2.census.gov/geo/tiger/TIGER2026/STATE/tl_2026_us_state.zip',
   '2e17ea40dff3e00163eec87a26efa0b0ff7e8fe364a191bf1a7754dcb49ea326',
   'TIGER/Line 2026 (boundaries 2026-01-01)', 'Not copyrighted; acknowledge US Census Bureau'],
  ['counties', 'tl_2026_us_county.zip',
   'https://www2.census.gov/geo/tiger/TIGER2026/COUNTY/tl_2026_us_county.zip',
   'b527c9ba7aeb8f17ef118f026eae5e5a938aa1d00b873bc32342d0dce59321c0',
   'TIGER/Line 2026 (boundaries 2026-01-01)', 'Not copyrighted; acknowledge US Census Bureau']
].map(&:freeze).freeze

def fetch_source(scratch, source)
  directory, filename, url, digest = source
  archive = File.join(scratch, filename)
  unless File.file?(archive)
    system('curl', '-fL', '--retry', '2', '--connect-timeout', '20', url, '-o', archive) ||
      raise("download failed: #{url}")
  end
  raise "archive hash mismatch: #{filename}" unless Digest::SHA256.file(archive).hexdigest == digest

  destination = File.join(scratch, directory)
  FileUtils.mkdir_p(destination)
  members = directory == 'gshhg' ? %w[gshhs_f.b README.TXT LICENSE.TXT COPYING.LESSERv3] : []
  system('unzip', '-oq', archive, *members, '-d', destination) || raise("unzip failed: #{filename}")
  source + [File.size(archive)]
end

if $PROGRAM_NAME == __FILE__
  scratch, output = ARGV
  raise 'pass existing ProjectTmp scratch directory and metadata output directory' unless File.directory?(scratch.to_s)
  
  FileUtils.mkdir_p(output)
  CSV.open(File.join(output, 'provenance.csv'), 'w') do |csv|
    csv << %w[source archive url sha256 version license archive_bytes]
    SOURCES.each { |source| csv << fetch_source(scratch, source) }
  end
end
