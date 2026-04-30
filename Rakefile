# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rubygems/package_task'
require 'rake/extensiontask'

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

Gem::PackageTask.new(spec)

exttask = Rake::ExtensionTask.new do |ext|
  ext.name = 'tre_regex'
  ext.ext_dir = 'ext/tre_regex'
  ext.lib_dir = 'lib/tre_regex'
  ext.gem_spec = spec
  ext.cross_compile = true
  ext.cross_platform = PLATFORMS
  ext.cross_compiling do |native_spec|
    native_spec.files += Dir['lib/tre_regex/bin/**/*']
  end
end

desc 'Build native gem'
task 'gem:native' do
  require 'rake_compiler_dock'
  sh 'bundle config set cache_all true'

  PLATFORMS.each do |platform|
    RakeCompilerDock.sh "bundle install --local && rake native:#{platform} gem", platform:
  end

  RakeCompilerDock.sh 'bundle install --local && rake java gem', rubyvm: :jruby
rescue LoadError
  abort 'rake_compiler_dock is required to build native gems'
end

namespace 'gem' do
  desc 'Prepare native gem'
  task 'prepare' do
    require 'rake_compiler_dock'
    require 'io/console'

    sh 'bundle config set cache_all true'
    sh 'cp ~/.gem/gem-*.pem build/gem/ || true'

    RakeCompilerDock.set_ruby_cc_version(spec.required_ruby_version.as_list)
  rescue LoadError
    abort 'rake_compiler_dock is required for this task'
  end

  exttask.cross_platform.each do |platform|
    desc 'Build all native binary gems in parallel'
    multitask 'native' => platform

    desc "Build the native gem for #{platform}"
    task platform => 'prepare' do
      RakeCompilerDock.sh <<-EOFCOMMAND, platform:
        sudo apt-get update -qq &&
        sudo apt-get install -yq --no-install-recommends build-essential autoconf automake libtool gettext autopoint pkg-config &&
        bundle install --local &&
        bundle install --local && rake native:#{platform} gem RUBY_CC_VERSION='#{ENV.fetch('RUBY_CC_VERSION', nil)}'
      EOFCOMMAND
    end
  end
end

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # skip
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
rescue LoadError
  # skip
end

desc 'Validate RBS files'
task :rbs_validate do
  sh 'bundle exec rbs -I sig -r ffi validate'
end

task default: %i[compile rbs_validate rubocop spec]
