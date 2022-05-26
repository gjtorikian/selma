# frozen_string_literal: true

require "rake"

def build_lolhml
  lib = File.join(LOL_HTML_UPSTREAM_RELEASE_DIR, "liblolhtml.#{extension}")
  puts "Checking for #{lib}..."
  Rake::Task["dependencies:compile"].invoke unless File.exist?(lib)
  puts "Copying lolhtml library and headers"
  copy_packaged_binaries(File.join(LOL_HTML_UPSTREAM_RELEASE_DIR, "liblolhtml.#{extension}"),
    to_path: abs_path(LOL_HTML_DIR))
  copy_packaged_library_headers(to_path: abs_path(LOL_HTML_DIR), from: ["include"])
end
