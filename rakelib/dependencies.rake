# frozen_string_literal: true

require "open-uri"
require "fileutils"

def open_url_to_file(url, file)
  puts "Fetching #{url}..."
  File.open(file, "wb") do |f|
    uri = URI.parse(url)
    uri.open do |d|
      f.write(d.read)
    end
  end
  puts "Saved to #{file}"
end

def nokogiri_url(name)
  "https://raw.githubusercontent.com/sparklemotion/nokogiri/main/gumbo-parser/src/#{name}"
end

def nokogiri_path(name)
  File.join("ext", "selma", "nokogiri-gumbo-parser", name.to_s)
end

def ut_url(name)
  "https://raw.githubusercontent.com/troydhanson/uthash/master/src/#{name}"
end

def ut_path(path)
  File.join("ext", "selma", "uthash", path)
end

def houdini_url(name)
  "https://raw.githubusercontent.com/commonmark/cmark/master/src/#{name}"
end

def houdini_path(path)
  File.join("ext", "selma", "houdini", path)
end

def exec(cmd, argv = [], opts = {})
  args = argv.join(" ")
  IO.popen("#{cmd} #{args}").each do |line|
    p(line.chomp)
    output << line.chomp
  end
end

namespace "dependencies" do
  desc "Fetches external header dependencies"
  task "fetch" do
    FileUtils.rm_rf("ext/selma/nokogiri-gumbo-parser")
    Dir.mkdir("ext/selma/nokogiri-gumbo-parser")
    open_url_to_file(nokogiri_url("ascii.h"), nokogiri_path("ascii.h"))
    open_url_to_file(nokogiri_url("ascii.c"), nokogiri_path("ascii.c"))
    open_url_to_file(nokogiri_url("macros.h"), nokogiri_path("macros.h"))
    open_url_to_file(nokogiri_url("nokogiri_gumbo.h"), nokogiri_path("nokogiri_gumbo.h"))
    open_url_to_file(nokogiri_url("tag_lookup.h"), nokogiri_path("tag_lookup.h"))
    open_url_to_file(nokogiri_url("tag_lookup.c"), nokogiri_path("tag_lookup.c"))
    open_url_to_file(nokogiri_url("tag.c"), nokogiri_path("tag.c"))
    open_url_to_file(nokogiri_url("util.h"), nokogiri_path("util.h"))

    puts " \n* * *\n\n"
    FileUtils.rm_rf("ext/selma/uthash")
    Dir.mkdir("ext/selma/uthash")
    open_url_to_file(ut_url("utarray.h"), ut_path("utarray.h"))
    open_url_to_file(ut_url("utstring.h"), ut_path("utstring.h"))
    open_url_to_file(ut_url("uthash.h"), ut_path("uthash.h"))

    puts " \n* * *\n\n"
    FileUtils.rm_rf("ext/selma/houdini")
    Dir.mkdir("ext/selma/houdini")
    open_url_to_file(houdini_url("houdini.h"), houdini_path("houdini.h"))
    open_url_to_file(houdini_url("utf8.h"), houdini_path("utf8.h"))
    open_url_to_file(houdini_url("utf8.c"), houdini_path("utf8.c"))
    open_url_to_file(houdini_url("cmark_ctype.h"), houdini_path("cmark_ctype.h"))
    open_url_to_file(houdini_url("cmark_ctype.c"), houdini_path("cmark_ctype.c"))
    open_url_to_file(houdini_url("case_fold_switch.inc"), houdini_path("case_fold_switch.inc"))
    open_url_to_file(houdini_url("entities.inc"), houdini_path("entities.inc"))
    open_url_to_file(houdini_url("houdini_href_e.c"), houdini_path("houdini_href_e.c"))
    open_url_to_file(houdini_url("houdini_html_e.c"), houdini_path("houdini_html_e.c"))
    open_url_to_file(houdini_url("houdini_html_u.c"), houdini_path("houdini_html_u.c"))
  end

  desc "Compiles external dependencies"
  task "compile" do
    puts("Building lolhtml...")
    Dir.chdir(File.join("ext", "selma", "lol-html-upstream", "c-api")) do
      exec("cargo", ["build", "--release"])
    end
  end
end
