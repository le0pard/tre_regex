# frozen_string_literal: true

require_relative 'lib/tre_regex/version'

Gem::Specification.new do |spec|
  spec.name = 'tre_regex'
  spec.version = TreRegex::VERSION
  spec.authors = ['Oleksii Vasyliev']
  spec.email = ['leopard.not.a@gmail.com']
  spec.license = 'MIT'

  spec.summary = 'A fast Ruby FFI wrapper for the TRE approximate regex matching library'
  spec.description = [
    'TreRegex provides a high-performance Ruby interface to the TRE C library using FFI.',
    'It brings robust approximate (fuzzy) regular expression matching to Ruby, featuring',
    'multi-byte Unicode string safety, and granular error limits'
  ].join(' ')
  spec.homepage = 'https://github.com/le0pard/tre_regex'
  spec.required_ruby_version = '>= 3.3.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/le0pard/tre_regex'
  spec.metadata['changelog_uri'] = 'https://github.com/le0pard/tre_regex/releases'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/le0pard/tre_regex/issues'
  spec.metadata['documentation_uri'] = 'https://github.com/le0pard/tre_regex/blob/main/README.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.

  spec.files = %w[
    lib/**/*.rb
    ext/tre_regex/extconf.rb
    ext/tre_regex/tre_regex.c
    README.md
    LICENSE
    tre_regex.gemspec
  ].flat_map { |p| Dir[p] }
  spec.extensions = ['ext/tre_regex/extconf.rb']

  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  spec.add_dependency 'ffi', '>= 1.0'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
