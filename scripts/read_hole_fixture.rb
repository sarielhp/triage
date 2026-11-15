# frozen_string_literal: true

require 'json'

abort 'usage: read_hole_fixture.rb FILE.json' unless ARGV.length == 1
rings = JSON.parse(File.read(ARGV.fetch(0)))
$stdout.binmode
$stdout.write([rings.length].pack('Q<'))
rings.each do |ring|
  $stdout.write([ring.length].pack('Q<'))
  ring.each { |point| $stdout.write(point.first(2).map(&:to_f).pack('E2')) }
end
