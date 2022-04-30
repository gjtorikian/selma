# frozen_string_literal: true

require "bundler"
Bundler::GemHelper.install_tasks

require "rake/testtask"
Rake::TestTask.new("test") do |t|
  t.libs << "lib"
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
  t.warning = false
end

require "rubocop/rake_task"

RuboCop::RakeTask.new(:rubocop)

desc "Run benchmarks"
task :benchmark do
  if ENV["FETCH_PROGIT"]
    `rm -rf test/progit`
    `git clone https://github.com/progit/progit.git test/progit`
    langs = %w[ar az be ca cs de en eo es es-ni fa fi fr hi hu id it ja ko mk nl no-nb pl pt-br ro ru sr th tr uk vi zh zh-tw]
    langs.each do |lang|
      `cat test/progit/#{lang}/*/*.markdown >> test/benchinput.md`
    end
  end
  $LOAD_PATH.unshift "lib"
  load "test/benchmark.rb"
end
