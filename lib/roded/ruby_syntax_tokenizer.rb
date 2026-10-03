require "ripper"

module Roded
  # Maps Ripper lexical tokens to immutable per-line editor spans.
  class RubySyntaxTokenizer
    def spans(lines, rows)
      source_lines = Array(lines)
      Ripper.lex(source_lines.join("\n")).each do |(position, event, token, _state)|
        category = category_for(event)
        next unless category

        row = position[0] - 1
        column = character_column(source_lines[row], position[1])
        add_multiline_span(rows, row, column, token, category)
      end
    end

    private

    def category_for(event)
      case event
      when :on_comment, :on_embdoc then :comment
      when :on_tstring_beg, :on_tstring_content, :on_tstring_end, :on_regexp_beg, :on_regexp_end then :string
      when :on_kw then :keyword
      when :on_int, :on_float, :on_rational, :on_imaginary then :number
      when :on_symbeg, :on_label then :symbol
      end
    end

    def add_multiline_span(rows, row, column, text, category)
      text.split("\n", -1).each_with_index do |part, offset|
        current_row = row + offset
        break unless rows[current_row]
        next if part.empty?

        start = offset.zero? ? column : 0
        rows[current_row] << { start:, finish: start + part.length, category: }
      end
    end

    def character_column(line, byte_column)
      line.to_s.byteslice(0, byte_column).to_s.force_encoding(Encoding::UTF_8).length
    end
  end
end
