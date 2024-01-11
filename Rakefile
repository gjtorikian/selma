# frozen_string_literal: true

if ENV.fetch("DEBUG", false)
  require "amazing_print"
  require "debug"
end

# Gem Spec
require "bundler/gem_tasks"
SELMA_SPEC = Gem::Specification.load("selma.gemspec")

# Packaging
require "rubygems/package_task"
gem_path = Gem::PackageTask.new(SELMA_SPEC).define
desc "Package the Ruby gem"
task "package" => [gem_path]
