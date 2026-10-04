require_relative "editor_html_renderer"
require_relative "document_structure_operations"
require_relative "document_index"
require_relative "current_line_format"

module Roded
  module Frontends
    # Replaces only changed rich-text blocks, retaining the native document and layout.
    class QtDocumentRenderer
      include QtDocumentStructureOperations

      def initialize(editor)
        @editor = editor
      end

      def copy_from(other)
        @document = other.editor.document.clone
        @document.set_parent(@editor)
        @editor.set_document(@document)
        @snapshot = other.snapshot
        @lines = other.lines
        @blocks = other.blocks.dup
        @index = other.index.dup
      end

      def render(snapshot, text)
        lines = snapshot[:lines] || QtCursorMapper.lines_for(text)
        renderer = QtEditorHtmlRenderer.new(text, snapshot)
        render_document(snapshot, lines, renderer)
        @lines = lines
        @snapshot = snapshot
        index
      end

      def row_position(row) = @index.position(row)

      private

      def render_document(snapshot, lines, renderer)
        if @snapshot && @lines.length != lines.length
          @index = nil
          update_structure(snapshot, lines, renderer)
        elsif @snapshot
          update_rows(changed_rows(snapshot, lines), renderer)
        else
          load_document(renderer)
        end
      end

      def load_document(renderer)
        @index = nil
        @editor.set_html(renderer.render)
        @blocks = renderer.blocks
      end

      def changed_rows(snapshot, lines)
        rows = overlay_rows(@snapshot) + overlay_rows(snapshot)
        rows.concat(content_changes(snapshot, lines))
        rows.uniq.select { |row| row.between?(0, lines.length - 1) }.sort.reverse
      end

      def content_changes(snapshot, lines)
        return [] if @lines.equal?(lines) && @snapshot[:tokens].equal?(snapshot[:tokens])

        lines.each_index.select do |row|
          @lines[row] != lines[row] || @snapshot[:tokens]&.[](row) != snapshot[:tokens]&.[](row)
        end
      end

      def overlay_rows(snapshot)
        point = snapshot.fetch(:point)
        rows = [point[:row]]
        rows.concat(span_rows(point, snapshot[:mark])) if snapshot[:mark]
        highlight = snapshot[:highlight]
        rows.concat(span_rows(highlight[:start], highlight[:finish])) if highlight
        rows
      end

      def span_rows(first, last)
        minimum, maximum = [first[:row], last[:row]].minmax
        (minimum..maximum).to_a
      end

      def update_rows(rows, renderer)
        return load_document(renderer) if rows.length > 64

        cursor = @editor.text_cursor
        cursor.begin_edit_block
        rows.each { |row| update_block(cursor, row, renderer) }
      ensure
        cursor&.end_edit_block
      end

      def update_block(cursor, row, renderer)
        html = renderer.block_html(row)
        set_row_format(cursor, row, renderer.snapshot)
        return if @blocks[row] == html

        replace_block(cursor, row, html)
        @blocks[row] = html
        @index&.update(row, QtDocumentIndex.block_length(renderer.lines.fetch(row), row, renderer.snapshot))
      end

      def replace_block(cursor, row, html)
        if @index
          cursor.set_position(@index.position(row))
        else
          QtCursorMapper.move_to_row(cursor, row)
        end
        cursor.move_position(::Qt::QTextCursor::EndOfBlock, ::Qt::QTextCursor::KeepAnchor, 1)
        cursor.insert_html(html)
      end

      def set_row_format(cursor, row, snapshot)
        cursor.set_position(@index.position(row)) if @index
        QtCursorMapper.move_to_row(cursor, row) unless @index
        (@line_format ||= QtCurrentLineFormat.new(@editor)).apply(cursor, active: snapshot[:point][:row] == row)
      end

      protected

      attr_reader :editor, :snapshot, :lines, :blocks

      def index
        @index ||= QtDocumentIndex.new(@lines, @snapshot)
      end
    end
  end
end
