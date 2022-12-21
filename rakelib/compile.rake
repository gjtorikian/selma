# frozen_string_literal: true

desc "Compile the extension with debug symbols"
task "compile:debug" do
  ENV["RB_SYS_CARGO_PROFILE"] = "dev"
  Rake::Task["compile"].invoke
end
