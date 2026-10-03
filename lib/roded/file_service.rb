require "digest"
require "tempfile"

module Roded
  # Reads UTF-8 documents and replaces files without truncating their originals.
  class FileService
    ABSENT_REVISION = Object.new.freeze
    Revision = Struct.new(:digest, :device, :inode, :file_size, :mtime_sec, :mtime_nsec, keyword_init: true)
    ReadResult = Struct.new(:path, :content, :revision, keyword_init: true)

    class Conflict < StandardError; end
    class InvalidDocument < StandardError; end

    def read(filename)
      path = canonical_path(filename)
      content = File.binread(path).force_encoding(Encoding::UTF_8)
      validate_content!(content)
      ReadResult.new(path:, content:, revision: revision_for(path, content))
    end

    def create_new(filename)
      path = File.expand_path(filename)
      raise Errno::EEXIST, path if File.exist?(path) || File.symlink?(path)
      raise Errno::ENOENT, File.dirname(path) unless Dir.exist?(File.dirname(path))

      ReadResult.new(path:, content: "", revision: ABSENT_REVISION)
    end

    def write(filename, content, expected_revision: nil)
      path = canonical_path_for_write(filename)
      validate_content!(content)
      verify_revision!(path, expected_revision) if expected_revision

      mode = File.exist?(path) ? File.stat(path).mode & 0o7777 : 0o666 & ~File.umask
      replace_atomically(path, content, mode)
      ReadResult.new(path:, content:, revision: revision_for(path, content))
    end

    def path_identity(filename)
      canonical_path_for_write(filename)
    end

    private

    def canonical_path(filename)
      File.realpath(File.expand_path(filename))
    end

    def canonical_path_for_write(filename)
      expanded_path = File.expand_path(filename)
      File.exist?(expanded_path) ? File.realpath(expanded_path) : expanded_path
    end

    def validate_content!(content)
      unless content.encoding == Encoding::UTF_8 && content.valid_encoding?
        raise InvalidDocument, "file is not valid UTF-8"
      end
      raise InvalidDocument, "binary files are not supported" if content.include?("\0")
      raise InvalidDocument, "mixed line endings are not supported" if content.scan(/\r\n|\n/).uniq.length > 1
    end

    def verify_revision!(path, expected_revision)
      if expected_revision.equal?(ABSENT_REVISION)
        raise Conflict, "file appeared on disk after the buffer was created" if File.exist?(path) || File.symlink?(path)

        return
      end

      current = revision_for(path, File.binread(path).force_encoding(Encoding::UTF_8))
      raise Conflict, "file changed on disk since it was opened" unless current == expected_revision
    rescue Errno::ENOENT
      raise Conflict, "file was removed from disk since it was opened"
    end

    def revision_for(path, content)
      stat = File.stat(path)
      Revision.new(
        digest: Digest::SHA256.hexdigest(content), device: stat.dev, inode: stat.ino,
        file_size: stat.size, mtime_sec: stat.mtime.to_i, mtime_nsec: stat.mtime.nsec
      ).freeze
    end

    def replace_atomically(path, content, mode)
      directory = File.dirname(path)
      Tempfile.create([".roded-", ".tmp"], directory, binmode: true) do |temporary|
        temporary.write(content)
        temporary.flush
        temporary.chmod(mode)
        temporary.fsync
        temporary.close
        File.rename(temporary.path, path)
      end
    end
  end
end
