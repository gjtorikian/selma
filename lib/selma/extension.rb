# frozen_string_literal: true

# load the C
begin
  # native precompiled gems package shared libraries in <gem_dir>/lib/selma/<ruby_version>
  ::RUBY_VERSION =~ /(\d+\.\d+)/
  require_relative "#{Regexp.last_match(1)}/selma"
rescue LoadError => e
  if /GLIBC/.match?(e.message)
    warn(<<~WARNING)

      ERROR: It looks like you're trying to use Nokogiri as a precompiled native gem on a system
             with an unsupported version of glibc.

        #{e.message}

        If that's the case, then please install Nokogiri via the `ruby` platform gem:
            gem install selma --platform=ruby
        or:
            bundle config set force_ruby_platform true

        Please visit https://selma.org/tutorials/installing_selma.html for more help.

    WARNING
    raise e
  end

  # use "require" instead of "require_relative" because non-native gems will place C extension files
  # in Gem::BasicSpecification#extension_dir after compilation (during normal installation), which
  # is in $LOAD_PATH but not necessarily relative to this file (see nokogiri#2300)
  require "selma/selma"

  require "selma/sanitizer"
  require "selma/rewriter"
end
