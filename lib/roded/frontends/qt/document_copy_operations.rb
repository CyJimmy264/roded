module Roded
  module Frontends
    # Copies presentation state while keeping independently editable native documents.
    module QtDocumentCopyOperations
      def copy_from(other)
        plain_copy = copy_document_content(other) == :plain
        @snapshot = other.snapshot
        @lines = other.lines
        @blocks = other.blocks.dup
        @index = other.index.dup
        restore_copied_caret if plain_copy
      end

      private

      def copy_document_content(other)
        if plain_document?(other)
          @editor.set_plain_text(other.editor.to_plain_text)
          :plain
        else
          copy_native_document(other.editor)
          :rich
        end
      end

      def plain_document?(other)
        snapshot = other.snapshot
        @editor.respond_to?(:copy_document_from) && uniform_monospace_font?(other.editor) &&
          !snapshot[:mark] && !snapshot[:highlight] &&
          snapshot[:tokens].to_a.all? { |row| row.to_a.empty? }
      end

      def uniform_monospace_font?(source)
        @editor.font.family == "monospace" && source.font.family == "monospace"
      end

      def restore_copied_caret
        row = @snapshot.fetch(:point).fetch(:row)
        @blocks[row] = nil
        update_rows([row], QtEditorHtmlRenderer.new(@snapshot[:text], @snapshot))
      end

      def copy_native_document(source)
        return @editor.copy_document_from(source) if @editor.respond_to?(:copy_document_from)

        @document = source.document.clone
        @document.set_parent(@editor)
        @editor.set_document(@document)
      end
    end
  end
end
