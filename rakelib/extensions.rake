# frozen_string_literal: true

require "rbconfig"
require "shellwords"
require "amazing_print"

require "rake_compiler_dock"

require_relative "extensions/util"
require_relative "extensions/cross_rubies"

ENV["RUBY_CC_VERSION"] = CROSS_RUBIES.map(&:ver).uniq.join(":")

CROSS_RUBIES.each do |cross_ruby|
  task cross_ruby.dll_staging_path do |t| # rubocop:disable Rake/Desc
    verify_dll t.name, cross_ruby
  end
end

namespace "gem" do
  CROSS_RUBIES.find_all { |cr| cr.windows? || cr.linux? || cr.darwin? }.uniq.each do |ruby|
    version = ruby.version
    plat = ruby.platform
    desc "build native gem for #{plat} platform"
    task plat do
      setup = <<~SETUP_EXE
        rvm install "#{version}"
        rvm use #{version} &&
        gem install bundler --no-document &&
        bundle &&
        bundle exec rake gem:#{plat}:builder MAKE='nice make -j`nproc`'
      SETUP_EXE

      RakeCompilerDock.sh(setup, platform: plat, verbose: true)
    end

    namespace plat do
      desc "build native gem for #{plat} platform (guest container)"
      task "builder" do
        # use Task#invoke because the pkg/*gem task is defined at runtime
        Rake::Task["native:#{plat}"].invoke
        Rake::Task["pkg/#{SELMA_SPEC.full_name}-#{Gem::Platform.new(plat)}.gem"].invoke
      end
    end
  end

  desc "build native gems for windows"
  multitask "windows" => CROSS_RUBIES.find_all(&:windows?).map(&:platform).uniq

  desc "build native gems for linux"
  multitask "linux" => CROSS_RUBIES.find_all(&:linux?).map(&:platform).uniq

  desc "build native gems for darwin"
  multitask "darwin" => CROSS_RUBIES.find_all(&:darwin?).map(&:platform).uniq
end

require "rake/extensiontask"

Rake::ExtensionTask.new("selma", SELMA_SPEC.dup) do |ext|
  ext.source_pattern = "*.{c,cc,cpp,h}"

  ext.lib_dir = File.join(*["lib", "selma", ENV.fetch("FAT_DIR", nil)].compact)
  ext.config_options << ENV.fetch("EXTOPTS", nil)
  ext.cross_compile  = true
  ext.cross_platform = CROSS_RUBIES.map(&:platform).uniq
  ext.cross_config_options << "--enable-cross-build"
  ext.cross_compiling do |spec|
    spec.files.reject! { |path| File.fnmatch?("ext/selma/lol-html-upstream/**/*", path) }
    spec.files.reject! { |path| File.fnmatch?("test/**/*", path) }

    # when pre-compiling a native gem, package all the C headers sitting in ext/selma/include
    # which were copied there in the $INSTALLFILES section of extconf.rb.
    headers_dir = "ext/selma/include"

    Dir.glob(File.join(headers_dir, "**", "*.h")).each do |header|
      spec.files << header
    end
  end
end
