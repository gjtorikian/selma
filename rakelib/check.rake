# frozen_string_literal: true

# replacement for Hoe's task of the same name

desc "Perform a sanity check on the gemspec file list"
task :check_manifest do
  raw_gemspec = Bundler.load_gemspec("selma.gemspec")

  ignore_directories = [".bundle", ".DS_Store", ".git", ".github", ".vagrant", ".yardoc", "coverage", "doc", "gems",
                        "misc", "patches", "pkg", "test/progit", "rakelib", "script", "sorbet", "suppressions", "test", "tmp", "vendor", "[0-9]*",]
  ignore_files = [".cross_rubies", ".editorconfig", ".gitignore", ".gitmodules", ".yardopts", ".rubocop.yml",
                  "CHANGELOG.md", "CODE_OF_CONDUCT.md", "CONTRIBUTING.md", "Gemfile?*", "Rakefile", "Vagrantfile", "[a-z]*.{log,out}", "[0-9]*", "ext/selma/lol-html-upstream/**/*", "lib/selma/**/selma.{jar,so,dylib}", "lib/selma/selma.{jar,so,dylib}", "selma.gemspec",]

  intended_directories = Dir.children(".")
    .select { |filename| File.directory?(filename) }
    .reject { |filename| ignore_directories.any? { |ig| File.fnmatch?(ig, filename) } }

  intended_files = Dir.children(".")
    .select { |filename| File.file?(filename) }
    .reject { |filename| ignore_files.any? { |ig| File.fnmatch?(ig, filename, File::FNM_EXTGLOB) } }

  intended_files += Dir.glob(intended_directories.map { |d| File.join(d, "/**/*") })
    .select { |filename| File.file?(filename) }
    .reject { |filename| ignore_files.any? { |ig| File.fnmatch?(ig, filename, File::FNM_EXTGLOB) } }
    .sort

  spec_files = raw_gemspec.files.sort

  missing_files = intended_files - spec_files
  extra_files = spec_files - intended_files

  unless missing_files.empty?
    puts "missing:"
    missing_files.sort.each { |f| puts "- #{f}" }
  end
  unless extra_files.empty?
    puts "unexpected:"
    extra_files.sort.each { |f| puts "+ #{f}" }
  end
end
