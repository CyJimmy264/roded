module Roded
  module Frontends
    # Removes toolkit defaults so editor panes meet their borders cleanly.
    module QtLayoutSpacing
      def self.reset(layout)
        layout.set_contents_margins(0, 0, 0, 0)
        layout.set_spacing(0)
      end

      def self.configure_pane(container, layout, editor, modeline)
        container.set_layout(layout)
        reset(layout)
        editor.set_contents_margins(0, 0, 0, 0)
        modeline.set_object_name("rodedModeline")
        modeline.set_margin(0)
      end
    end
  end
end
