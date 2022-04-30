# frozen_string_literal: true

require "bundler"
Bundler::GemHelper.install_tasks

require "rake/testtask"

task default: :test

Rake::TestTask.new("test") do |t|
  t.libs << "lib"
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
  t.warning = false
end
