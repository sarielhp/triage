# frozen_string_literal: true

require 'csv'
require 'digest'
require 'fileutils'
require 'zlib'

# Archive extraction is deliberately separate: pass an existing ProjectTmp tree.
# Inventory stores every individual ring, never a multipolygon vertex total.
def gshhg_rings(path)
  File.open(path, 'rb') do |io|
    until io.eof?
      header = io.read(44).unpack('l>*')
      raise 'bad GSHHG header' unless header.length == 11 && header[1] >= 3

      id, n, flag = header[0, 3]
      bytes = io.read(8 * n)
      raise 'truncated GSHHG coordinates' unless bytes.bytesize == 8 * n
      yield({ source: 'gshhg', id: id.to_s, part: 0, raw_n: n,
              level: flag & 255, exterior: true, offset: io.pos - 8 * n,
              west: header[3], east: header[4], flags: flag }, bytes)
    end
  end
end

def dbf_names(path)
  data = File.binread(path)
  count = data[4, 4].unpack1('V')
  header, size = data[8, 4].unpack('vv')
  fields = (32...(header - 1)).step(32).map do |offset|
    [data[offset, 11].delete("\0"), data.getbyte(offset + 16)]
  end
  Array.new(count) do |i|
    offset = header + i * size + 1
    fields.to_h do |name, width|
      value = data[offset, width].strip
      offset += width
      [name, value]
    end
  end
end

def shape_parts(data)
  raise 'expected Polygon shape' unless data.unpack1('V') == 5

  parts, count = data[36, 8].unpack('VV')
  raise 'bad Polygon record length' unless parts.positive? && data.bytesize == 44 + 4 * parts + 16 * count
  starts = data[44, 4 * parts].unpack('V*') + [count]
  raise 'bad part offsets' unless starts.first.zero? && starts.each_cons(2).all? { |a, b| b - a >= 4 }
  point_offset = 44 + 4 * parts
  starts.each_cons(2).with_index.map do |(first, last), part|
    bytes = data[point_offset + first * 16, (last - first) * 16]
    points = bytes.unpack('E*').each_slice(2).to_a
    # ESRI Polygon exterior rings are clockwise; the sign only classifies parts.
    area = points.each_cons(2).sum { |a, b| a[0] * b[1] - a[1] * b[0] }
    magnitude = points.flatten.map(&:abs).max
    bound = 64 * Float::EPSILON * points.length**2 * magnitude**2
    area = points.each_cons(2).sum { |a, b| a[0].to_r * b[1].to_r - a[1].to_r * b[0].to_r } if area.abs <= bound
    [part, last - first, area.negative?, bytes]
  end
end

def tiger_rings(path, source)
  names = dbf_names(path.sub(/\.shp\z/, '.dbf'))
  File.open(path, 'rb') do |io|
    header = io.read(100)
    raise 'bad shapefile header' unless header.unpack1('N') == 9994 && header[24, 4].unpack1('N') * 2 == io.size
    until io.eof?
      record, words = io.read(8).unpack('NN')
      data = io.read(words * 2)
      raise 'truncated shape record' unless data.bytesize == words * 2
      name = names.fetch(record - 1)
      shape_parts(data).each do |part, n, exterior, bytes|
        yield({ source: source, id: name.fetch('GEOID'), name: name.fetch('NAME'),
                part: part, raw_n: n, exterior: exterior, level: 1 }, bytes)
      end
    end
  end
end

def rings(scratch, &block)
  gshhg_rings(File.join(scratch, 'gshhg/gshhs_f.b'), &block)
  tiger_rings(File.join(scratch, 'states/tl_2026_us_state.shp'), 'states', &block)
  tiger_rings(File.join(scratch, 'counties/tl_2026_us_county.shp'), 'counties', &block)
end

def select_rings(inventory)
  inventory.select { |r| r[:exterior] && r[:level] < 5 && r[:raw_n] >= 5000 }
           .group_by { |r| [r[:source], r[:raw_n] < 30_000 ? 0 : (r[:raw_n] < 100_000 ? 1 : 2)] }
           .flat_map do |(source, _stratum), entries|
    sorted = entries.sort_by { |r| [r[:raw_n], r[:id], r[:part]] }
    count = [source == 'gshhg' ? 4 : 2, sorted.length].min
    indices = count == 1 ? [0] : (0...count).map { |i| i * (sorted.length - 1) / (count - 1) }
    sorted.values_at(*indices)
  end
end

def save_selected(scratch, selected)
  lookup = selected.to_h { |r| [[r[:source], r[:id], r[:part]], r] }
  rings(scratch) do |row, bytes|
    chosen = lookup[[row[:source], row[:id], row[:part]]]
    next unless chosen

    points = bytes.unpack(row[:source] == 'gshhg' ? 'l>*' : 'E*').each_slice(2).to_a
    chosen[:original_ring_sha256] = Digest::SHA256.hexdigest(bytes)
    chosen[:original_closed] = points.first == points.last
    chosen[:original_min_lon], chosen[:original_max_lon] = points.map(&:first).minmax
    original_longitudes = points.map(&:first)
    # Continuously unwrap longitude; no splitting or new vertices.
    period = row[:source] == 'gshhg' ? 360_000_000 : 360.0
    points.each_cons(2) do |a, b|
      b[0] -= period while b[0] - a[0] > period / 2
      b[0] += period while b[0] - a[0] < -period / 2
    end
    chosen[:longitude_shifted_vertices] = points.each_index.count { |i| points[i][0] != original_longitudes[i] }
    chosen[:unwrapped_min_lon], chosen[:unwrapped_max_lon] = points.map(&:first).minmax
    chosen[:unwrapped_closed] = points.first == points.last
    chosen[:case] = "#{row[:source]}-#{row[:id]}-#{row[:part]}"
    path = File.join(scratch, 'rings', "#{chosen[:case]}.raw.bin")
    File.binwrite(path, [points.length].pack('Q<') + points.flatten.pack('E*'))
    chosen[:raw_sha256] = Digest::SHA256.file(path).hexdigest
  end
end

if $PROGRAM_NAME == __FILE__
  scratch, output = ARGV
  FileUtils.mkdir_p([output, File.join(scratch, 'rings')])
  inventory = []
  rings(scratch) { |row, _bytes| inventory << row }
  selected = select_rings(inventory)
  save_selected(scratch, selected)
  keys = %i[source id part raw_n level exterior name case raw_sha256 original_ring_sha256
            original_closed original_min_lon original_max_lon longitude_shifted_vertices
            unwrapped_min_lon unwrapped_max_lon unwrapped_closed]
  Zlib::GzipWriter.open(File.join(output, 'inventory.csv.gz')) do |io|
    io.write(CSV.generate_line(keys))
    inventory.each { |row| io.write(CSV.generate_line(row.values_at(*keys))) }
  end
  CSV.open(File.join(output, 'selected.csv'), 'w') do |csv|
    csv << keys
    selected.each { |row| csv << row.values_at(*keys) }
  end
  inventory.group_by { |r| r[:source] }.each do |source, entries|
    counts = entries.select { |r| r[:exterior] }.map { |r| r[:raw_n] }
    puts "#{source}: #{entries.length} rings; exterior max #{counts.max}; >=10k #{counts.count { |n| n >= 10_000 }}; >=100k #{counts.count { |n| n >= 100_000 }}; >=1m #{counts.count { |n| n >= 1_000_000 }}"
  end
  puts "Selected #{selected.length} standalone boundaries before timing."
end
