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
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  spec.metadata["source_code_uri"] = "https://github.com/gjtorikian/selma"

  spec.files         = `git ls-files -z`.split("\x0").grep_v(%r{^(test|gemfiles|script)/})
  spec.require_paths = ["lib"]

  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "nokogiri", "~> 1.13"
  spec.add_dependency "zeitwerk", "~> 2.5"

  spec.add_development_dependency "amazing_print"

  spec.add_development_dependency "rake"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "minitest-focus", "~> 1.2"

  spec.add_development_dependency "rubocop-standard"

  # spec.add_development_dependency "debug", ">= 1.0.0"
end
