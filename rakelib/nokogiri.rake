# frozen_string_literal: true

require "open-uri"
require "FileUtils"

def open_url_to_file(url, file)
  File.open(file, "wb") do |f|
    uri = URI.parse(url)
    uri.open do |d|
      f.write(d.read)
    end
  end
end

namespace "nokogiri" do
  desc "Gets Gumbo header file"
  task "fetch:headers" do
    FileUtils.rm_rf("ext/selma/nokogiri")
    Dir.mkdir("ext/selma/nokogiri")
    open_url_to_file("https://raw.githubusercontent.com/sparklemotion/nokogiri/main/gumbo-parser/src/attribute.h", "ext/selma/nokogiri/attribute.h")
    open_url_to_file("https://raw.githubusercontent.com/sparklemotion/nokogiri/main/gumbo-parser/src/macros.h", "ext/selma/nokogiri/macros.h")
    open_url_to_file("https://raw.githubusercontent.com/sparklemotion/nokogiri/main/gumbo-parser/src/nokogiri_gumbo.h", "ext/selma/nokogiri/nokogiri_gumbo.h")
    open_url_to_file("https://raw.githubusercontent.com/sparklemotion/nokogiri/main/gumbo-parser/src/parser.c", "ext/selma/parser.c")
    open_url_to_file("https://raw.githubusercontent.com/sparklemotion/nokogiri/main/gumbo-parser/src/parser.h", "ext/selma/parser.h")
    open_url_to_file("https://raw.githubusercontent.com/sparklemotion/nokogiri/main/gumbo-parser/src/string_buffer.h", "ext/selma/nokogiri/string_buffer.h")
    open_url_to_file("https://raw.githubusercontent.com/sparklemotion/nokogiri/main/gumbo-parser/src/util.h", "ext/selma/nokogiri/util.h")
    open_url_to_file("https://raw.githubusercontent.com/sparklemotion/nokogiri/main/gumbo-parser/src/vector.h", "ext/selma/nokogiri/vector.h")
  end
end
