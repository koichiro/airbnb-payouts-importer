# frozen_string_literal: true

require "bundler"
require "rake/testtask"

LINT_GEMFILE = File.expand_path("Gemfile.lint", __dir__)

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.libs << "lib"
  task.pattern = "test/**/*_test.rb"
  task.verbose = true
end

desc "Lint Ruby files with Standard Ruby"
task :lint do
  Bundler.with_unbundled_env do
    sh({"BUNDLE_GEMFILE" => LINT_GEMFILE}, "bundle", "exec", "standardrb", ".", "Gemfile.lint")
  end
end

task default: :test
