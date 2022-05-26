# frozen_string_literal: true

require "rubocop/rake_task"

RuboCop::RakeTask.new(:rubocop)

module AstyleHelper
  class << self
    def run(files)
      assert
      command = ["astyle", args, files].flatten.shelljoin
      system(command)
    end

    def assert
      require "mkmf"
      find_executable0("astyle") || raise("Could not find command 'astyle'")
    end

    def args
      # See http://astyle.sourceforge.net/astyle.html
      # Taken, like so much else, from Nokogiri
      [
        # indentation
        "--indent=spaces=2",
        "--indent-switches",

        # brackets
        "--style=1tbs",
        "--keep-one-line-blocks",

        # where do we want spaces
        "--unpad-paren",
        "--pad-header",
        "--pad-oper",
        "--pad-comma",

        # "void *pointer" and not "void* pointer"
        "--align-pointer=name",

        # function definitions and declarations
        "--break-return-type",
        "--attach-return-type-decl",

        # gotta set a limit somewhere
        "--max-code-length=120",

        # be quiet about files that haven't changed
        "--formatted",
        "--verbose",

        "--suffix=none",
      ]
    end

    def c_files
      ["ext/selma/*.c", "ext/selma/*.h"]
    end
  end
end

namespace "format" do
  desc "Format Selma C code"
  task "c" do
    puts "Running astyle on C files ..."
    AstyleHelper.run(AstyleHelper.c_files)
  end

  CLEAN.add(AstyleHelper.c_files.map { |f| "#{f}.orig" })
end
