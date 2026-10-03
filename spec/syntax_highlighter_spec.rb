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
