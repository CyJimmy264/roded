# rubocop:disable Metrics/BlockLength
RSpec.describe Roded::Keymap do
  it "uses XDG_CONFIG_HOME for the default keymap path" do
    previous = ENV.fetch("XDG_CONFIG_HOME", nil)
    ENV["XDG_CONFIG_HOME"] = "/tmp/roded-test-config"

    expect(described_class.default_path).to eq("/tmp/roded-test-config/roded/keymap.yml")
  ensure
    ENV["XDG_CONFIG_HOME"] = previous
  end

  it "loads valid custom bindings alongside defaults" do
    Dir.mktmpdir("roded-keymap") do |directory|
      path = File.join(directory, "keymap.yml")
      File.write(path, "C-c t:\n  type: ruby_repl\n")

      keymap = described_class.load(path)

      expect(keymap.resolve("C-c t")).to eq(type: :ruby_repl, payload: {})
      expect(keymap.resolve("C-n")).to eq(type: :move_down, payload: {})
      expect(keymap.load_warning).to be_nil
    end
  end

  it "falls back to defaults and reports malformed configuration" do
    Dir.mktmpdir("roded-keymap") do |directory|
      path = File.join(directory, "keymap.yml")
      File.write(path, "C-c t: [")

      keymap = described_class.load(path)

      expect(keymap.resolve("C-n")).to eq(type: :move_down, payload: {})
      expect(keymap.resolve("C-c t")).to be_nil
      expect(keymap.load_warning).to include("Ignoring keymap", "keymap.yml")
    end
  end

  it "rejects invalid binding entries instead of silently ignoring them" do
    Dir.mktmpdir("roded-keymap") do |directory|
      path = File.join(directory, "keymap.yml")
      File.write(path, "C-c t:\n  type: does_not_exist\n")

      keymap = described_class.load(path)

      expect(keymap.resolve("C-c t")).to be_nil
      expect(keymap.load_warning).to include("unknown command type")
    end
  end

  it "shows a configuration warning in the active frontend after startup" do
    application = Roded::Application.new
    frontend = FakeFrontend.new
    application.instance_variable_set(:@frontends, [frontend])
    application.instance_variable_set(:@configuration_warning, "Ignoring keymap /tmp/keymap.yml: bad entry")

    application.startup

    expect(frontend.messages.last).to eq("Ignoring keymap /tmp/keymap.yml: bad entry")
  end
end
# rubocop:enable Metrics/BlockLength
