# frozen_string_literal: true

require_relative 'geographic/extract'

def gshhg_index(path)
  rows = []
  File.open(path, 'rb') do |io|
    until io.eof?
      header = io.read(44).unpack('l>*')
      rows << { id: header[0], n: header[1], level: header[2] & 255,
                parent: header[9], offset: io.pos }
      io.seek(8 * header[1], IO::SEEK_CUR)
    end
  end
  rows
end

def unwrap(points, period)
  result = points.map(&:dup)
  result.each_cons(2) do |a, b|
    b[0] -= period while b[0] - a[0] > period / 2
    b[0] += period while b[0] - a[0] < -period / 2
  end
  result
end

def read_gshhg_polygon(io, outer, holes)
  rings = [outer, *holes].map do |row|
    io.seek(row.fetch(:offset))
    raw = io.read(8 * row.fetch(:n)).unpack('l>*').each_slice(2).to_a
    unwrap(raw, 360_000_000)
  end
  center = rings.first.sum(&:first).to_f / rings.first.length
  rings.drop(1).each do |ring|
    hole_center = ring.sum(&:first).to_f / ring.length
    shift = ((center - hole_center) / 360_000_000).round * 360_000_000
    ring.each { |p| p[0] += shift }
  end
  rings
end

def select_gshhg(scratch)
  path = File.join(scratch, 'gshhg/gshhs_f.b')
  rows = gshhg_index(path)
  children = rows.select { |r| r[:level] == 2 }.group_by { |r| r[:parent] }
  eligible = rows.select do |r|
    r[:level] == 1 && r[:n].between?(5000, 100_000) && children.key?(r[:id])
  end
  selected = eligible.sort_by { |r| [-r[:n], r[:id]] }.first(3)
  source_hash = Digest::SHA256.file(path).hexdigest
  File.open(path, 'rb') do |io|
    selected.map do |outer|
      holes = children.fetch(outer[:id]).sort_by { |r| r[:id] }
      rings = read_gshhg_polygon(io, outer, holes)
      ["gshhg-#{outer[:id]}", 'gshhg', outer[:id], '',
       [outer, *holes].map { |r| r[:id] }.join(';'), source_hash, rings]
    end
  end
end

def census_inventory
  path = File.join(File.dirname(ARGV[2]), 'inventory.csv.gz')
  Zlib::GzipReader.open(path) { |io| CSV.new(io, headers: true).read }
      .reject { |r| r['source'] == 'gshhg' }
      .group_by { |r| [r['source'], r['id']] }
end

def select_census(scratch)
  groups = census_inventory.select do |_, rows|
    rows.count { |r| r['exterior'] == 'true' } == 1 &&
      rows.any? { |r| r['exterior'] == 'false' }
  end
  chosen = groups.sort_by { |key, rows| [-rows.sum { |r| r['raw_n'].to_i }, key] }.first(7).to_h
  polygons = chosen.to_h { |key, _| [key, []] }
  %w[states counties].each do |source|
    shape = source == 'states' ? 'state' : 'county'
    path = File.join(scratch, source, "tl_2026_us_#{shape}.shp")
    tiger_rings(path, source) do |row, bytes|
      key = [source, row[:id]]
      next unless polygons.key?(key)
      polygons.fetch(key) << [row[:exterior], row[:part], bytes.unpack('E*').each_slice(2).to_a]
    end
  end
  chosen.map do |key, rows|
    parts = polygons.fetch(key).sort_by { |exterior, part, _| [exterior ? 0 : 1, part] }
    source, id = key
    shape = source == 'states' ? 'state' : 'county'
    hash = Digest::SHA256.file(File.join(scratch, source, "tl_2026_us_#{shape}.shp")).hexdigest
    ["#{source}-#{id}", source, id, rows.first['name'], parts.map { |p| p[1] }.join(';'), hash, parts.map(&:last)]
  end
end

def write_cases(path, cases, metadata)
  File.open(path, 'wb') do |io|
    io.write([cases.length].pack('Q<'))
    CSV.open(metadata, 'w') do |csv|
      csv << %w[case source feature_id name ring_ids source_sha256 raw_vertices holes raw_polygon_sha256]
      cases.each do |row|
        rings = row.last
        bytes = [rings.length].pack('Q<')
        rings.each { |ring| bytes << [ring.length].pack('Q<') << ring.flatten.pack('E*') }
        io.write(bytes)
        csv << row.first(6) + [rings.sum(&:length), rings.length - 1, Digest::SHA256.hexdigest(bytes)]
      end
    end
  end
end

abort 'usage: extract_hole_geography.rb SOURCE_SCRATCH RAW.bin METADATA.csv' unless ARGV.length == 3
cases = select_census(ARGV[0]) + select_gshhg(ARGV[0])
write_cases(ARGV[1], cases, ARGV[2])
puts "Extracted #{cases.length} complete connected geographic components with their holes."
