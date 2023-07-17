# frozen_string_literal: true

source "https://rubygems.org"

# Specified gem's dependencies in selma.gemspec
gemspec

gem "github_changelog_generator", "~> 1.16"

group :debug do
  gem "amazing_print"
  gem "debug"
end

group :development, :test do
  gem "ruby_memcheck"
end

group :test do
  gem "gemojione", "~> 4.3", require: false
  gem "minitest", "~> 5.0"
  gem "minitest-focus", "~> 1.2"
  gem "minitest-spec-context", "~> 0.0.4"
end

group :lint do
  gem "rubocop-standard"
end

group :benchmark do
  # benchmark stuff
  gem "benchmark-ips"
  gem "commonmarker"
  gem "gemoji"
  gem "html-pipeline"
  gem "rouge"
  gem "sanitize", "~> 6.0"
end

gem "ruby-lsp", "~> 0.7.0", group: :development
