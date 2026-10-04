require "spec_helper"
require "roded/frontends/curses"

RSpec.describe Roded::Frontends::CursesKeyTranslator do
  it "normalizes terminal NUL and control bytes while preserving Unicode" do
    decoder = described_class.new

    expect(decoder.send(:normalize_input, "\0")).to eq("C-SPC")
    expect(decoder.send(:normalize_input, "\u0001")).to eq("C-a")
    expect(decoder.send(:normalize_input, "\u001f")).to eq("C-_")
    expect(decoder.send(:normalize_input, "\t")).to eq("Tab")
    expect(decoder.send(:normalize_input, "\b")).to eq("C-h")
    expect(decoder.send(:normalize_input, "\u007F")).to eq("Backspace")
    expect(decoder.send(:normalize_input, "Ж")).to eq("Ж")
  end

  it "maps xterm navigation and function-key sequences" do
    translator = described_class.new
    sequences = {
      "[H" => "Home", "[F" => "End", "[5~" => "PageUp", "[6~" => "PageDown",
      "[3~" => "Delete", "[18~" => "F7", "OP" => "F1", "[24~" => "F12",
      "[47;5u" => "C-/", "[47;6u" => "C-?", "[110;5u" => "C-n",
      "[127u" => "Backspace", "[57352;5u" => "C-Up", "[46;4u" => "M->",
      "[44;4u" => "M-<"
    }

    decoded = sequences.to_h do |sequence, _key|
      [sequence, translator.translate_escape(sequence)]
    end
    expect(decoded).to eq(sequences)
  end
end

RSpec.describe Roded::Frontends::CursesKeyTranslator, "CSI-u decoding" do
  it "waits for and recognizes fragmented CSI-u key sequences" do
    translator = described_class.new

    expect(translator.timeout("[110;", "[200~")).to be > 0.03
    expect(translator.complete_sequence?("[110;5u", "[200~")).to be(true)
    expect(translator.translate_escape("[110;5u")).to eq("C-n")
  end
end

RSpec.describe Roded::Frontends::CursesInputDecoder do
  it "decodes UTF-8 characters read across terminal bytes" do
    decoder = described_class.new
    input, writer, wake_reader, wake_writer = decoder_pipes
    writer.write("Ж🙂")

    expect(decoder.read_key(input, wake_reader)).to eq("Ж")
    expect(decoder.read_key(input, wake_reader)).to eq("🙂")
  ensure
    [input, writer, wake_reader, wake_writer].compact.each(&:close)
  end
end

RSpec.describe Roded::Frontends::CursesInputDecoder do
  it "returns EOF when terminal input is closed" do
    decoder = described_class.new
    input, writer, wake_reader, wake_writer = decoder_pipes
    writer.close

    expect(decoder.read_key(input, wake_reader)).to be_nil
  ensure
    [input, writer, wake_reader, wake_writer].compact.each { |pipe| pipe.close unless pipe.closed? }
  end
end

RSpec.describe Roded::Frontends::CursesInputDecoder do
  it "decodes bracketed multiline paste and preserves following keys" do
    decoder = described_class.new
    input, writer, wake_reader, wake_writer = decoder_pipes
    writer.write("[200~first\nвторой\e[201~x")

    paste = decoder.send(:read_escape_sequence, input, wake_reader)

    expect(paste).to eq(described_class::PasteInput.new("first\nвторой"))
    expect(decoder.send(:read_input_key, input, wake_reader)).to eq("x")
  ensure
    [input, writer, wake_reader, wake_writer].compact.each(&:close)
  end
end

RSpec.describe Roded::Frontends::CursesInputDecoder do
  it "waits for a fragmented bracketed paste start marker" do
    decoder = described_class.new
    input, writer, wake_reader, wake_writer = decoder_pipes
    writer.write("[20")
    continuation = Thread.new do
      sleep(0.02)
      writer.write("0~fragmented\e[201~")
    end

    paste = decoder.send(:read_escape_sequence, input, wake_reader)
    continuation.join

    expect(paste).to eq(described_class::PasteInput.new("fragmented"))
  ensure
    [input, writer, wake_reader, wake_writer].compact.each(&:close)
    continuation&.join
  end
end

RSpec.describe Roded::Frontends::Curses do
  it "emits a core paste event instead of a keyboard event" do
    frontend = described_class.allocate
    paste = Roded::Frontends::CursesInputDecoder::PasteInput.new("first\nsecond")
    allow(frontend).to receive(:read_key).and_return(paste)

    event = frontend.next_event

    expect(event.type).to eq(:paste)
    expect(event.payload).to eq(text: "first\nsecond")
  end

  it "propagates terminal EOF to the runtime" do
    frontend = described_class.allocate
    allow(frontend).to receive(:read_key).and_return(nil)

    expect(frontend.next_event).to be_nil
  end
end

def decoder_pipes
  input, writer = IO.pipe
  wake_reader, wake_writer = IO.pipe
  [input, writer, wake_reader, wake_writer]
end

RSpec.describe Roded::Frontends::CursesInputDecoder, "consecutive terminal keys" do
  it "preserves keys arriving immediately after a Meta key" do
    decoder = described_class.new
    input, writer, wake_reader, wake_writer = decoder_pipes
    writer.write("\egg32\r\x06\x02")
    keys = Array.new(7) { decoder.read_key(input, wake_reader) }
    expect(keys).to eq(%w[M-g g 3 2 Enter C-f C-b])
  ensure
    [input, writer, wake_reader, wake_writer].compact.each(&:close)
  end

  it "preserves a Unicode Meta key and escape sequences buffered after paste" do
    decoder = described_class.new
    input, writer, wake_reader, wake_writer = decoder_pipes
    writer.write("\e[200~text\e[201~\eЖ\e[D\x02")
    expect(decoder.read_key(input, wake_reader)).to eq(described_class::PasteInput.new("text"))
    expect(Array.new(3) { decoder.read_key(input, wake_reader) }).to eq(%w[M-Ж Left C-b])
  ensure
    [input, writer, wake_reader, wake_writer].compact.each(&:close)
  end
end
