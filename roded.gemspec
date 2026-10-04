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

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/CyJimmy264/roded"
  spec.metadata["changelog_uri"] = "https://github.com/CyJimmy264/roded/blob/v#{Roded::VERSION}/CHANGELOG.md"

  # Runtime and maintained documentation; development artifacts stay in the checkout.
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "bin/roded", "docs/*.md", "README.md", "CHANGELOG.md", "LICENSE"].sort
  end

  spec.bindir = "bin"
  spec.executables = ["roded"]
  spec.require_paths = ["lib"]

  spec.add_dependency "curses", "~> 1.5"
  spec.add_dependency "logger", "~> 1.6"
  spec.add_dependency "prism", "~> 1.6"
  spec.add_dependency "qt", "~> 0.2.0"
  spec.add_dependency "unicode-display_width", "~> 3.2"

  spec.metadata["rubygems_mfa_required"] = "true"
end
