# frozen_string_literal: true

require 'digest'
require 'fileutils'
require_relative 'geographic/fetch'

EARCUT_COMMIT = '9e70986eb94054c621c926888dd05bc26bffb902'
EARCUT_ARCHIVE_SHA = '900485264a5e3413d937dd2eaade8573b137ca424c023221e4f905d9cc049c94'

def download_tiles(destination)
  archive = File.join(destination, 'earcut-js.tar.gz')
  url = "https://codeload.github.com/mapbox/earcut/tar.gz/#{EARCUT_COMMIT}"
  unless File.file?(archive)
    system('curl', '-fL', '--retry', '2', '--connect-timeout', '20', url, '-o', archive) ||
      raise('Earcut fixture download failed')
  end
  raise 'Earcut archive checksum mismatch' unless Digest::SHA256.file(archive).hexdigest == EARCUT_ARCHIVE_SHA

  root = File.join(destination, 'earcut-js')
  FileUtils.mkdir_p(root)
  system('tar', '-xzf', archive, '--strip-components=1', '-C', root) || raise('tar extraction failed')
  puts "Earcut JS fixtures: #{root}"
end

abort 'usage: download.rb DESTINATION [--geography]' unless ARGV.length.between?(1, 2)
abort 'unknown option' if ARGV[1] && ARGV[1] != '--geography'

destination = File.expand_path(ARGV[0])
FileUtils.mkdir_p(destination)
download_tiles(destination)
if ARGV[1] == '--geography'
  metadata = File.join(destination, 'provenance')
  FileUtils.mkdir_p(metadata)
  CSV.open(File.join(metadata, 'sources.csv'), 'w') do |csv|
    csv << %w[source archive url sha256 version license archive_bytes]
    SOURCES.each { |source| csv << fetch_source(destination, source) }
  end
end
