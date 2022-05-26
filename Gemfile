# frozen_string_literal: true

source "https://rubygems.org"

# Specified gem's dependencies in selma.gemspec
gemspec

# test stuff
group :local, :development, :test do
  gem "amazing_print"
  gem "rubocop-standard"
  gem "ruby_memcheck"
end

group :local, :development do
  gem "debug", "~> 1.0"
end

group :test do
  gem "minitest", "~> 5.0"
  gem "minitest-focus", "~> 1.2"
  gem "minitest-spec-context", "~> 0.0.4"
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
