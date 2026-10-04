require "spec_helper"
require_relative "../lib/roded/frontends/qt"

RSpec.describe Roded::Frontends::QtWindowTheme do
  around do |example|
    previous = ENV.fetch("QT_STYLE_OVERRIDE", nil)
    ENV.delete("QT_STYLE_OVERRIDE")
    example.run
  ensure
    previous ? ENV["QT_STYLE_OVERRIDE"] = previous : ENV.delete("QT_STYLE_OVERRIDE")
  end

  it "selects Fusion during application creation and restores the process environment" do
    style = nil
    allow(QApplication).to receive(:new) { style = ENV.fetch("QT_STYLE_OVERRIDE") }
    described_class.create_application
    expect(style).to eq("Fusion")
    expect(ENV).not_to have_key("QT_STYLE_OVERRIDE")
  end

  it "preserves an explicitly selected Qt style" do
    ENV["QT_STYLE_OVERRIDE"] = "Breeze"
    allow(QApplication).to receive(:new) { ENV.fetch("QT_STYLE_OVERRIDE") }
    expect(described_class.create_application).to eq("Breeze")
    expect(ENV.fetch("QT_STYLE_OVERRIDE")).to eq("Breeze")
  end

  it "restores automatic style selection when application construction fails" do
    allow(QApplication).to receive(:new).and_raise("construction failed")
    expect { described_class.create_application }.to raise_error("construction failed")
    expect(ENV).not_to have_key("QT_STYLE_OVERRIDE")
  end
end
