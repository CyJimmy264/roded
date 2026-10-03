require "tmpdir"

RSpec.describe Roded::FilePathProvider do
  it "lists files and parent directories outside Git while excluding caches" do
    Dir.mktmpdir("roded-paths") do |root|
      FileUtils.mkdir_p(File.join(root, "src"))
      FileUtils.mkdir_p(File.join(root, "node_modules", "pkg"))
      File.write(File.join(root, "src", "main.rb"), "")
      File.write(File.join(root, "node_modules", "pkg", "index.js"), "")

      candidates = described_class.new(root).candidates

      expect(candidates).to include("src/", "src/main.rb")
      expect(candidates).not_to include("node_modules/", "node_modules/pkg/index.js")
      expect(candidates).to be_frozen
    end
  end

  it "honors Git ignore rules and omits the Git metadata directory" do
    Dir.mktmpdir("roded-git-paths") do |root|
      system("git", "-C", root, "init", "-q", exception: true)
      File.write(File.join(root, ".gitignore"), "ignored/\n")
      FileUtils.mkdir_p(File.join(root, "visible"))
      FileUtils.mkdir_p(File.join(root, "ignored"))
      File.write(File.join(root, "visible", "note.md"), "")
      File.write(File.join(root, "ignored", "cache"), "")

      candidates = described_class.new(root).candidates

      expect(candidates).to include("visible/", "visible/note.md", ".gitignore")
      expect(candidates).not_to include("ignored/", "ignored/cache", ".git/")
    end
  end
end
