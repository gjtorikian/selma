# frozen_string_literal: true

# rubocop:disable Style/GlobalVars

require "mkmf"
require "amazing_print"
require "open3"

require_relative "_util"
require_relative "_config"
require_relative "_help"

if debug?
  puts "Compiling in debug mode (using Ruby #{RUBY_VERSION})..."
  append_cflags("-Wextra")
  # remember: set DYLD_INSERT_LIBRARIES, and
  # use a non-shim ruby
  append_cflags("-fno-omit-frame-pointer")
  append_cflags("-fno-optimize-sibling-calls")
  CONFIG["debugflags"] = "-ggdb -g"
  CONFIG["optflags"] = "-O0"
end

require_relative "_cflags"

puts "Building selma using packaged libraries."

static_p = config_static?
puts "Static linking is #{static_p ? "enabled" : "disabled"}."

cross_build_p = config_cross_build?
puts "Cross build is #{cross_build_p ? "enabled" : "disabled"}."

RbConfig::CONFIG["CC"] = RbConfig::MAKEFILE_CONFIG["CC"] = ENV.fetch("CC", nil) if ENV["CC"]

# use same c compiler for libxml and libxslt
ENV["CC"] = RbConfig::CONFIG["CC"]

require_relative "_lolhtml"

build_lolhml

# "symlink" other source files.
Dir.chdir(PACKAGE_EXT_DIR) do
  $srcs = Dir["*.c", File.join(NK_GUMBO_DIR, "*.c"), File.join(HOUDINI_DIR, "*.c")]
  $hdrs = Dir["*.h", File.join(NK_GUMBO_DIR, "*.h"), File.join(LOL_HTML_DIR, "*.h"), File.join(UTHASH_DIR, "*.h"), File.join(HOUDINI_DIR, "*.h")]
end

$INCFLAGS << " -I$(srcdir)/#{UTHASH_DIR} -I$(srcdir)/#{HOUDINI_DIR} -I$(srcdir)/#{NK_GUMBO_DIR}"
$VPATH << "$(srcdir)/#{UTHASH_DIR}  $(srcdir)/#{HOUDINI_DIR} $(srcdir)/#{NK_GUMBO_DIR}"

if cross_build_p
  # When precompiling native gems, copy packaged libraries' headers to ext/selma/include
  # These are packaged up by the cross-compiling callback in the ExtensionTask
  copy_packaged_library_headers(from: [NK_GUMBO_DIR, LOL_HTML_DIR, UTHASH_DIR, HOUDINI_DIR],
    to_path: File.join(PACKAGE_ROOT_DIR, "ext/selma/include"))
else
  # When compiling during installation, install packaged libraries' header files into ext/selma/include
  copy_packaged_library_headers(from: [NK_GUMBO_DIR, LOL_HTML_DIR, UTHASH_DIR, HOUDINI_DIR], to_path: "include")
  $INSTALLFILES << ["#{LOL_HTML_DIR}/*.h", "$(rubylibdir)"]
end

dir_config("lolhtml", [abs_path(LOL_HTML_DIR)], [abs_path(LOL_HTML_DIR)])
$LIBS << " -llolhtml"
find_header_or_abort("lol_html.h", abs_path(LOL_HTML_DIR))
find_library_or_abort("lolhtml", "lol_html_selector_parse", abs_path(LOL_HTML_DIR)) unless asan?

if asan?
  have_library("asan")

  append_cflags("-fsanitize=address")
  $LDFLAGS << " -fsanitize=address"
end

if debug?
  srcs = $srcs.join("\n* ")
  hdrs = $hdrs.join("\n* ")
  libs = $LIBS.split.join("\n* ")
  message <<~FILES

    # Sources

    * #{srcs}

    # Headers

    * #{hdrs}

    # Libraries

    * #{libs}

  FILES

  old_cflags = $CFLAGS.split.join(" ")
  old_ldflags = $LDFLAGS.split.join(" ")
  old_dldflags = $DLDFLAGS.split.join(" ")
  $CFLAGS = $CFLAGS.split.reject { |flag| flag == "-s" }.join(" ")
  $LDFLAGS = $LDFLAGS.split.reject { |flag| flag == "-s" }.join(" ")
  $DLDFLAGS = $DLDFLAGS.split.reject { |flag| flag == "-s" }.join(" ")
  puts "Prevent stripping by removing '-s' from $CFLAGS" if old_cflags != $CFLAGS
  puts "Prevent stripping by removing '-s' from $LDFLAGS" if old_ldflags != $LDFLAGS
  puts "Prevent stripping by removing '-s' from $DLDFLAGS" if old_dldflags != $DLDFLAGS
end

create_makefile("selma/selma")

if config_clean?
  # Do not clean if run in a development work tree.
  File.open("Makefile", "at") do |mk|
    mk.print(<<~CLEANUP_TARGET)

      all: clean-ports
      clean-ports: $(DLLIB)
      \t-$(Q)$(RUBY) $(srcdir)/extconf.rb --clean --#{static_p ? "enable" : "disable"}-static
    CLEANUP_TARGET
  end
end

# rubocop:enable Style/GlobalVars
