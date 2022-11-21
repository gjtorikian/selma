# frozen_string_literal: true

RUBY_MAJOR, RUBY_MINOR = RUBY_VERSION.split(".").collect(&:to_i)

PACKAGE_ROOT_DIR = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))
PACKAGE_EXT_DIR = File.join(PACKAGE_ROOT_DIR, "ext", "selma")

REQUIRED_MINI_PORTILE_VERSION = "~> 2.8.0" # keep this version in sync with the one in the gemspec

# Keep track of what versions of what libraries we build against
OTHER_LIBRARY_VERSIONS = {}.freeze

LOL_HTML_UPSTREAM_DIR = File.join(PACKAGE_EXT_DIR, "lol-html-upstream")
LOL_HTML_UPSTREAM_C_API_DIR = File.join(LOL_HTML_UPSTREAM_DIR, "c-api")
LOL_HTML_UPSTREAM_RELEASE_DIR = File.join(LOL_HTML_UPSTREAM_C_API_DIR, "target", "release")
LOL_HTML_DIR = "liblolhtml"
NK_GUMBO_DIR = "nokogiri-gumbo-parser"
UTHASH_DIR = "uthash"
HOUDINI_DIR = "houdini"

def windows?
  RbConfig::CONFIG["target_os"].match?(/mingw|mswin/)
end

def solaris?
  RbConfig::CONFIG["target_os"].include?("solaris")
end

def darwin?
  RbConfig::CONFIG["target_os"].include?("darwin")
end

def macos?
  darwin? || RbConfig::CONFIG["target_os"].include?("macos")
end

def openbsd?
  RbConfig::CONFIG["target_os"].include?("openbsd")
end

def aix?
  RbConfig::CONFIG["target_os"].include?("aix")
end

def nix?
  !(windows? || solaris? || darwin?)
end

def chdir_for_build(&block)
  # Windows and Linux have symlink issues using rake-compiler-dock on
  # Work around this limitation by using the temp dir for cooking.
  build_dir = /mingw|mswin|cygwin/.match?(ENV["RCD_HOST_RUBY_PLATFORM"].to_s) ? "/tmp" : "."
  Dir.chdir(build_dir, &block)
end

def abs_path(path)
  File.join(PACKAGE_EXT_DIR, path)
end

def copy_packaged_library_headers(to_path:, from:)
  FileUtils.mkdir_p(to_path)
  from.each do |header_loc|
    FileUtils.cp_r(Dir[File.join(header_loc, "*.h")], to_path)
  end
end

def copy_packaged_binaries(bin_loc, to_path:)
  FileUtils.mkdir_p(to_path)
  FileUtils.cp(bin_loc, to_path)
end

def extension
  macos? ? "dylib" : "so"
end

def find_header_or_abort(header, *paths)
  find_header(header, *paths) || abort("lol_html.h was expected in `#{paths.join(", ")}`, but it is missing.")
end

def find_library_or_abort(lib, func, *paths)
  find_library(lib, func, *paths) || abort("#{lib} was expected in `#{paths.join(", ")}`, but it is missing.")
end
