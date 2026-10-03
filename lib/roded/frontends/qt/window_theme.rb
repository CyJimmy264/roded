module Roded
  module Frontends
    # Applies the shared dark palette to Qt editor windows.
    module QtWindowTheme
      def self.apply(window)
        window.set_style_sheet(
          "QWidget { background: #292b34; color: #bbc2cf; } " \
          "QTextEdit { background: #282c34; color: #bbc2cf; border: 0; " \
          "selection-background-color: #3e4451; } QLabel { padding: 4px; }"
        )
      end
    end
  end
end
