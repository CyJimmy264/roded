require "open3"
require "rbconfig"

RSpec.describe Roded do
  it "has a version number" do
    expect(Roded::VERSION).not_to be nil
  end

  it "loads the shared editor core without loading curses" do
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-Ilib",
      "-e",
      'require "roded"; abort "curses loaded" if $LOADED_FEATURES.any? { |path| path.end_with?("/curses.rb") }'
    )

    expect(status).to be_success, stderr
  end
end
