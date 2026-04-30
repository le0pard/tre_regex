# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rubygems/package_task'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'rake/extensiontask'
require 'rake_compiler_dock'

PLATFORMS = %w[
  aarch64-linux-gnu
  aarch64-linux-musl
  arm-linux-gnu
  arm-linux-musl
  arm64-darwin
  x86_64-darwin
  x86_64-linux-gnu
  x86_64-linux-musl
  x86-linux-gnu
  x86-linux-musl
].freeze
spec = Gem::Specification.load('tre_regex.gemspec')

RakeCompilerDock.set_ruby_cc_version(spec.required_ruby_version.as_list)

Gem::PackageTask.new(spec).define

exttask = Rake::ExtensionTask.new do |ext|
  ext.name = 'tre_regex'
  ext.ext_dir = 'ext/tre_regex'
  ext.lib_dir = 'lib/tre_regex'
  ext.gem_spec = spec
  ext.cross_compile = true
  ext.cross_platform = PLATFORMS
  ext.cross_compiling do |native_spec|
    if native_spec.platform.to_s.include?('darwin')
      native_spec.files << 'lib/tre_regex/bin/libtre.dylib'
    elsif native_spec.platform.to_s.include?('mingw') || native_spec.platform.to_s.include?('mswin')
      native_spec.files << 'lib/tre_regex/bin/tre.dll'
    else
      native_spec.files << 'lib/tre_regex/bin/libtre.so'
    end
  end
end

namespace 'gem' do
  exttask.cross_platform.each do |platform|
    desc "Build the native gem for #{platform}"
    task platform do
      RakeCompilerDock.sh <<-EOFCOMMAND, platform:
        sudo apt-get update -qq &&
        sudo apt-get install -yq --no-install-recommends build-essential autoconf automake libtool gettext autopoint pkg-config &&
        bundle install &&
        bundle exec rake gem:#{platform}:buildit RUBY_CC_VERSION='#{ENV.fetch('RUBY_CC_VERSION', nil)}'
      EOFCOMMAND
    end

    namespace platform do
      desc 'this runs in the rake-compiler-dock docker container'
      task 'buildit' do
        # use Task#invoke because the pkg/*gem task is defined at runtime
        Rake::Task["native:#{platform}"].invoke
        Rake::Task["pkg/#{spec.full_name}-#{Gem::Platform.new(platform)}.gem"].invoke
      end
    end
  end

  desc 'build native gem for all platforms'
  multitask 'all' => [exttask.cross_platform, 'gem'].flatten
end

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

desc 'Validate RBS files'
task :rbs_validate do
  sh 'bundle exec rbs -I sig -r ffi validate'
end

desc 'Package all gems'
task 'package' => 'gem:all'

task default: %i[compile rbs_validate rubocop spec]
