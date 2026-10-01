# frozen_string_literal: true

require "rake/testtask"
require "standard/rake"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.libs << "lib"
  task.pattern = "test/**/*_test.rb"
  task.verbose = true
end

desc "Lint Ruby files with Standard Ruby"
task lint: :standard

task default: :test
