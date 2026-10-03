require "open3"

module Roded
  # Lists project-visible paths for file-open completion and project pickers.
  class FilePathProvider
    EXCLUDED = %w[.git .bundle node_modules vendor/cache coverage tmp].freeze

    def initialize(root = Dir.pwd)
      @root = File.expand_path(root)
    end

    def candidates
      git_root ? git_candidates : filesystem_candidates
    end

    private

    def git_root
      output, _error, status = Open3.capture3("git", "-C", @root, "rev-parse", "--show-toplevel")
      return unless status.success?

      output.strip
    end

    def git_candidates
      output, _error, status = Open3.capture3(
        "git", "-C", @root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"
      )
      return [] unless status.success?

      output.split("\0").flat_map { |path| with_parent_directories(path) }.uniq.sort.freeze
    end

    def filesystem_candidates
      files = Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH)
                 .select { |path| File.file?(path) && !excluded?(path) }
                 .map { |path| path.delete_prefix("#{@root}/") }
      files.flat_map { |path| with_parent_directories(path) }.uniq.sort.freeze
    end

    def with_parent_directories(path)
      parts = path.split(File::SEPARATOR)
      directories = (1...parts.length).map { |index| "#{parts.first(index).join(File::SEPARATOR)}/" }
      directories + [path]
    end

    def excluded?(path)
      relative = path.delete_prefix("#{@root}/")
      relative.split(File::SEPARATOR).any? { |part| EXCLUDED.include?(part) || part == "." || part == ".." }
    end
  end
end
