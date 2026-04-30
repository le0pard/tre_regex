# frozen_string_literal: true

require_relative 'lib/tre_regex/version'

Gem::Specification.new do |spec|
  spec.name = 'tre_regex'
  spec.version = TreRegex::VERSION
  spec.authors = ['Oleksii Vasyliev']
  spec.email = ['leopard.not.a@gmail.com']

  spec.summary = 'Write a short summary, because RubyGems requires one.'
  spec.description = 'Write a longer description or delete this line.'
  spec.homepage = "https://github.com/le0pard/tre_regex"
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = "https://github.com/le0pard/tre_regex"
  spec.metadata['source_code_uri'] = 'https://github.com/le0pard/tre_regex'
  spec.metadata['changelog_uri'] = 'https://github.com/le0pard/tre_regex/releases'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/le0pard/tre_regex/issues'
  spec.metadata['documentation_uri'] = 'https://github.com/le0pard/tre_regex/blob/main/README.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  File.basename(__FILE__)

  spec.files = Dir['lib/**/*.rb']

  if spec.platform == Gem::Platform::RUBY
    # If building the source gem, include the C source and the extconf.rb
    spec.files += Dir['ext/**/*.{c,h,in,rb}']
    spec.extensions = ['ext/tre_regex/extconf.rb']
  else
    # If building a platform gem (Linux/Mac/Windows), include the compiled binaries
    spec.files += Dir['lib/**/*.{so,dylib,dll}']
  end

  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  spec.add_dependency 'ffi', '>= 1.0'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
