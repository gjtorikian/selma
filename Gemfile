# frozen_string_literal: true

source "https://rubygems.org"

# Specified gem's dependencies in selma.gemspec
gemspec

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
  gem "benchmark-ips"
  gem "nokolexbor"
  gem "sanitize"
end

gem "ruby-lsp", "~> 0.11", group: :development
