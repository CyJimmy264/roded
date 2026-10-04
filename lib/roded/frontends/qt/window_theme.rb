module Roded
  module Frontends
    # Applies the shared dark palette to Qt editor windows.
    module QtWindowTheme
      def self.apply(window)
        window.set_style_sheet(
          "QWidget { background: #292b34; color: #bbc2cf; margin: 0px; padding: 0px; } " \
          "QTextEdit, QPlainTextEdit { background: #282c34; color: #bbc2cf; font-family: monospace; border: 0; " \
          "selection-background-color: #3e4451; } " \
          "QLabel { padding: 0px; margin: 0px; border: 0px; } " \
          "QLabel#rodedModeline { border-top: 1px solid #4b5263; }"
        )
      end
    end
  end
end
