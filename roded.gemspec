require_relative "lib/roded/version"

Gem::Specification.new do |spec|
  spec.name = "roded"
  spec.version = Roded::VERSION
  spec.authors = ["Maksim Veynberg"]
  spec.email = ["mv@cj264.ru"]

  spec.summary = "Ruby Object-oriented Development Environment eDitor"
  spec.description = "Roded (Ruby Object-oriented Development Environment eDitor) is a programmable " \
                     "editor and development environment in Ruby. The long-term goal is an editor that " \
                     "is fully scriptable from inside and outside (like Emacs with Elisp), but with " \
                     "Ruby as the extension language and a clean, frontend-agnostic core."
  spec.homepage = "https://roded.cj264.ru/"
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = ">= 3.4.2"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  # spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[test/ spec/ features/ .git appveyor Gemfile])
    end
  end

  spec.bindir = "bin"
  spec.executables = ["roded"]
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "curses"
  spec.add_dependency "logger"
  spec.add_dependency "qt", "~> 0.2.0"
  spec.add_dependency "unicode-display_width", "~> 3.2"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata["rubygems_mfa_required"] = "true"
end
