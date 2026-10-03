require "spec_helper"

# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::FileService do
  subject(:service) { described_class.new }

  it "writes through a temporary file while preserving file mode" do
    Tempfile.create("roded-file-service") do |file|
      File.chmod(0o640, file.path)

      service.write(file.path, "saved\n")

      expect(File.binread(file.path)).to eq("saved\n")
      expect(File.stat(file.path).mode & 0o777).to eq(0o640)
    end
  end

  it "keeps a symlink and atomically updates its target" do
    Dir.mktmpdir("roded-symlink") do |directory|
      target = File.join(directory, "target.txt")
      link = File.join(directory, "link.txt")
      File.write(target, "before")
      File.symlink(target, link)

      result = service.read(link)
      service.write(link, "after", expected_revision: result.revision)

      expect(File.symlink?(link)).to be(true)
      expect(File.binread(target)).to eq("after")
    end
  end

  it "rejects saving over a file changed after it was opened" do
    Tempfile.create("roded-conflict") do |file|
      file.write("before")
      file.flush
      result = service.read(file.path)
      File.write(file.path, "external change")

      expect do
        service.write(file.path, "editor change", expected_revision: result.revision)
      end.to raise_error(Roded::FileService::Conflict)
      expect(File.binread(file.path)).to eq("external change")
    end
  end

  it "rejects binary and mixed-line-ending documents" do
    expect { service.write("/tmp/roded-invalid", "a\0b") }
      .to raise_error(Roded::FileService::InvalidDocument, /binary/)
    expect { service.write("/tmp/roded-invalid", "a\nb\r\n") }
      .to raise_error(Roded::FileService::InvalidDocument, /mixed line endings/)
  end

  it "does not create missing parent directories" do
    Dir.mktmpdir("roded-no-parent") do |directory|
      path = File.join(directory, "missing", "new.txt")

      expect { service.write(path, "text") }.to raise_error(Errno::ENOENT)
      expect(File.exist?(File.dirname(path))).to be(false)
    end
  end

  it "detects a file created after a new buffer was made" do
    Dir.mktmpdir("roded-new-file-conflict") do |directory|
      path = File.join(directory, "new.txt")
      result = service.create_new(path)
      File.write(path, "external")

      expect do
        service.write(path, "editor", expected_revision: result.revision)
      end.to raise_error(Roded::FileService::Conflict, /appeared on disk/)
      expect(File.binread(path)).to eq("external")
    end
  end
end
# rubocop:enable Metrics/BlockLength
