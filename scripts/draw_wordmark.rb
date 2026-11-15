# frozen_string_literal: true

require_relative 'tmp_space'
require 'fileutils'

ProjectTmp.project = 'triage'
scratch = ProjectTmp.mktmpdir('wordmark')
cache = File.join(scratch, 'ipe-latex')
FileUtils.mkdir_p(cache)
root = File.expand_path('..', __dir__)
puts "Figure scratch: #{scratch}"
$stdout.flush
environment = { 'TMPDIR' => scratch, 'IPELATEXDIR' => cache }
script = File.join(root, 'julia/figures/triage-wordmark.jl')
exec(environment, 'julia', script)
