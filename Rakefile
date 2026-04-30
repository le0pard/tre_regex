# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/extensiontask'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

spec = Gem::Specification.load('tre_regex.gemspec')

Rake::ExtensionTask.new('tre_regex', spec) do |ext|
  ext.ext_dir = 'ext/tre_regex'
  ext.lib_dir = 'lib/tre_regex'

  ext.cross_compile = true

  ext.cross_platform = %w[
    x86_64-linux
    aarch64-linux
    x86_64-darwin
    arm64-darwin
    x64-mingw-ucrt
  ]

  ext.cross_compiling do |native_spec|
    native_spec.files += Dir['lib/tre_regex/bin/**/*']
  end
end

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

desc 'Validate RBS files'
task :rbs_validate do
  sh 'bundle exec rbs -I sig -r ffi validate'
end

task default: %i[compile rbs_validate rubocop spec]
