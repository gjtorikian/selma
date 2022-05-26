# frozen_string_literal: true

require_relative "lib/selma/version"

Gem::Specification.new do |spec|
  spec.name          = "selma"
  spec.version       = Selma::VERSION
  spec.authors       = ["Garen J. Torikian"]
  spec.email         = ["gjtorikian@gmail.com"]

  spec.summary       = "Write a short summary, because RubyGems requires one."
  spec.description   = "Write a longer description or delete this line."

  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new("~> 3.0")

  spec.metadata["source_code_uri"] = "https://github.com/gjtorikian/selma"

  spec.files         = ["Gemfile", "LICENSE.txt", "README.md", "Rakefile", "selma.gemspec"]
  spec.files        += Dir.glob("lib/**/*.rb")
  spec.files        += Dir["ext/selma/*{.rb,.c,.h}"]
  spec.files        += Dir["ext/selma/liblolhtml/**/*"]
  spec.files        += Dir["ext/selma/nokogiri-gumbo-parser/**/*"]
  spec.files        += Dir["ext/selma/uthash/**/*"]
  spec.files        += Dir["ext/selma/entities/**/*"]
  spec.files        += Dir["bin/**/*"]

  spec.bindir = "bin"
  spec.executables = spec.files.grep(/^bin/) { |f| File.basename(f) }

  spec.require_paths = ["lib"]

  spec.homepage = "https://github.com/gjtorikian/selma"
  spec.metadata = {
    "funding_uri" => "https://github.com/sponsors/gjtorikian/",
    "homepage_uri" => "https://github.com/gjtorikian/selma",
    "bug_tracker_uri" => "https://github.com/gjtorikian/selma/issues",
    "source_code_uri" => "https://github.com/gjtorikian/selma",
    "rubygems_mfa_required" => "true",
  }

  spec.add_development_dependency("rake", "~> 13.0")
  spec.add_development_dependency("rake-compiler", "~> 1.1")
  spec.add_development_dependency("rake-compiler-dock", "~> 1.2")
end
