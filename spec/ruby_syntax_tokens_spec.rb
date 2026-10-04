require "spec_helper"

module RubySyntaxTokensSpecSupport
  def colored_characters(spans, lines)
    lines.each_index.map do |row|
      colors = Array.new(lines[row].length)
      spans[row].each { |span| (span[:start]...span[:finish]).each { |column| colors[column] = span[:category] } }
      colors
    end
  end

  def ripper_spans(lines)
    tokens = Object.new
    def tokens.each(source)
      Ripper.lex(source).each { |position, event, text, _state| yield position, event, text }
    end
    tokenizer = Roded::RubySyntaxTokenizer.new
    tokenizer.instance_variable_set(:@tokens, tokens)
    rows = lines.map { [] }
    tokenizer.spans(lines, rows)
    rows
  end
end

RSpec.describe Roded::SyntaxHighlighter, "Ruby row reuse" do
  it "shares unchanged spans while recomputing rows whose multiline lexical context changed" do
    highlighter = described_class.new
    lines = ["# header", "number = 42", 'message = "open', "shared line"].map(&:freeze).freeze
    before = highlighter.spans(:ruby, lines)
    changed = ["# edited".freeze, lines[1], "# closed string".freeze, lines[3]].freeze
    after = highlighter.spans(:ruby, changed)
    expect(after).to eq(described_class.new.spans(:ruby, changed))
    expect(after[1]).to equal(before[1])
    expect(before[3]).to include(hash_including(category: :string))
    expect(after[3]).to be_empty
    expect(after[3]).not_to equal(before[3])
    expect(after).to be_frozen
    expect(after.flatten).to all(be_frozen)
  end
end

module RubySyntaxTokensSpecSupport
  SOURCES = [
    'def привет(x: 42); puts "🙂#{x}"; end # comment',
    "x = [1, 1.2, 1r, 1i, 1.2ri, 0xff]; :symbol; 'string'; /regexp/i",
    "%w[one two]; %W[one \#{two}]; %i[one two]; %I[one \#{two}]; %q(a); %Q(a\#{b})",
    "=begin\nembedded comment\n=end\ntrue unless false",
    "message = \"unfinished\nстрока 🙂", "def incomplete(", "a = { count: 1, label: \"hi\" }",
    "if (\n42\nend\n# after error",
    "text = <<~DOC\n  строка 🙂\n    more\nDOC\n42",
    "text = <<-DOC\n  строка 🙂\nDOC", "a, b = <<~FIRST, <<~SECOND\n  one\nFIRST\n  two\nSECOND",
    "text = <<~DOC\n  \#{42}\n    text\nDOC", "text = <<~DOC\n  unfinished",
    "a = \"one\\\ntwo\"; b = /строка\n42/", "x = \"🙂\"; 42\n\tputs :имя",
    "__END__\nuncolored data 42 def", "a = `echo 42`; ?x; :\"quoted символ\""
  ].freeze
end

RSpec.describe Roded::RubySyntaxTokens, "lexical compatibility" do
  include RubySyntaxTokensSpecSupport

  RubySyntaxTokensSpecSupport::SOURCES.each_with_index do |source, index|
    it "matches Ripper's colored characters for lexical corpus entry #{index + 1}" do
      lines = source.split("\n", -1)
      actual = Roded::SyntaxHighlighter.new.spans(:ruby, lines)
      expect(colored_characters(actual, lines)).to eq(colored_characters(ripper_spans(lines), lines))
    end
  end

  it "matches Ripper on the editor's tokenizer and rich-text renderer source" do
    %w[ruby_syntax_tokenizer.rb frontends/qt/editor_html_renderer.rb application.rb].each do |path|
      lines = File.read(File.expand_path("../lib/roded/#{path}", __dir__)).split("\n", -1)
      actual = Roded::SyntaxHighlighter.new.spans(:ruby, lines)
      expect(colored_characters(actual, lines)).to eq(colored_characters(ripper_spans(lines), lines))
    end
  end
end

RSpec.describe Roded::RubySyntaxTokens, "parser recovery" do
  it "keeps useful label, string and number colors after an invalid block prefix" do
    lines = ['a = invalid{ count: 1, label: "hi" }']
    spans = Roded::SyntaxHighlighter.new.spans(:ruby, lines).first
    expect(spans).to include(hash_including(category: :number), hash_including(category: :string),
                             hash_including(start: 23, finish: 29, category: :symbol))
    expect(spans).to all(satisfy { |span| span[:start] >= 0 && span[:finish] <= lines.first.length })
  end
end
