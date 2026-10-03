RSpec.describe Roded::SyntaxHighlighter do
  subject(:highlighter) { described_class.new }

  it "highlights Ruby keywords, strings, comments, and numbers across lines" do
    spans = highlighter.spans(:ruby, ["def greet", "  puts \"hi\"", "end # done", "42"])
    categories = spans.flatten.map { |span| span[:category] }

    expect(categories).to include(:keyword, :string, :comment, :number)
    expect(spans).to be_frozen
    expect(spans.flatten).to all(be_frozen)
  end

  it "continues string spans across multiline Ruby tokens" do
    spans = highlighter.spans(:ruby, ["text = <<~DOC", "hello", "DOC"])

    expect(spans[1].map { |span| span[:category] }).to include(:string)
  end

  it "returns useful JSON, YAML, and Markdown token categories" do
    json = highlighter.spans(:json, ["{\"name\": \"Roded\", \"ok\": true, \"n\": 4}"])
    expect(json.flatten.map { |span| span[:category] })
      .to include(:string, :keyword, :number)
    expect(highlighter.spans(:yaml, ["name: \"Roded\" # editor"]).flatten.map { |span| span[:category] })
      .to include(:symbol, :string, :comment)
    expect(highlighter.spans(:markdown, ["# Title", "`code` **bold**"]).flatten.map { |span| span[:category] })
      .to include(:heading, :string, :keyword)
  end

  it "falls back to plain spans when a mode fails" do
    expect(highlighter.spans(:unknown, %w[plain text])).to eq([[], []])
  end
end

RSpec.describe Roded::SyntaxHighlighter, "tokenizer failures" do
  it "falls back to empty token rows when a tokenizer raises" do
    highlighter = described_class.new
    tokenizer = highlighter.instance_variable_get(:@ruby_tokenizer)
    allow(tokenizer).to receive(:spans).and_raise(ArgumentError, "malformed source")

    expect(highlighter.spans(:ruby, ["def unfinished"])).to eq([[]])
  end
end

RSpec.describe Roded::SyntaxHighlighter, "Ruby Unicode and incomplete source" do
  subject(:highlighter) { described_class.new }

  it "maps Ripper byte columns to character columns after non-ASCII text" do
    spans = highlighter.spans(:ruby, ["x = \"🙂\"; 42"]).first
    number = spans.find { |span| span[:category] == :number }

    expect(number).to include(start: 9, finish: 11)
  end

  it "continues highlighting an incomplete multiline Ruby string" do
    spans = highlighter.spans(:ruby, ["message = \"unfinished", "строка 🙂"])

    expect(spans.last).to include(hash_including(start: 0, finish: 8, category: :string))
  end
end
