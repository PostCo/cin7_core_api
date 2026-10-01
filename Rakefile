# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec)

task default: [:spec, :standard]
# Appending prerequisites to :release would run them after Bundler's push tasks.
task "release:guard_clean" => [:spec, :standard]
