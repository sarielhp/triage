# frozen_string_literal: true

require 'csv'
CSV.foreach(ARGV.fetch(0), headers: true) { |row| puts row.fetch('case') }
