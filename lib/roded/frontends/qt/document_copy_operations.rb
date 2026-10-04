module Roded
  module Frontends
    # Copies presentation state while keeping independently editable native documents.
    module QtDocumentCopyOperations
      def copy_from(other)
        copy_native_document(other.editor)
        @snapshot = other.snapshot
        @lines = other.lines
        @blocks = other.blocks.dup
        @index = other.index.dup
      end

      private

      def copy_native_document(source)
        return @editor.copy_document_from(source) if @editor.respond_to?(:copy_document_from)

        @document = source.document.clone
        @document.set_parent(@editor)
        @editor.set_document(@document)
      end
    end
  end
end
