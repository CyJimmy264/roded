require "qt"
require "roded"
require_relative "../lib/roded/frontends/qt/key_translator"
require_relative "../lib/roded/frontends/qt/input_router"
require_relative "../lib/roded/frontends/qt/clipboard_bridge"
require_relative "../lib/roded/frontends/qt/editor_window"

# rubocop:disable Metrics/BlockLength
RSpec.describe "Qt shortcut routing" do
  let(:translator) { Roded::Frontends::QtKeyTranslator.new }
  let(:router) { Roded::CommandRouter.new(Roded::Keymap.new(Roded::Keymap::DEFAULT)) }

  before(:context) do
    @qt_application = QApplication.new(0, ["roded-shortcut-spec"]) unless QApplication.instance_exists
  end

  it "routes actual Qt modifier payloads for the supported Super aliases" do
    aliases = [
      [{ key: Qt::Key_J, modifiers: Qt::AltModifier | Qt::MetaModifier, text: "j" }, :save_buffer],
      [{ key: Qt::Key_K, modifiers: Qt::AltModifier | Qt::MetaModifier, text: "k" }, :kill_buffer],
      [{ key: Qt::Key_C, modifiers: Qt::AltModifier | Qt::MetaModifier, text: "c" }, :delete_window],
      [{ key: Qt::Key_W, modifiers: Qt::MetaModifier, text: "w" }, :other_window],
      [{ key: Qt::Key_Left, modifiers: Qt::MetaModifier, text: "" }, :shrink_window_horizontally],
      [{ key: Qt::Key_Right, modifiers: Qt::MetaModifier, text: "" }, :enlarge_window_horizontally],
      [{ key: Qt::Key_Comma, modifiers: Qt::MetaModifier, text: "," }, :previous_buffer],
      [{ key: Qt::Key_Period, modifiers: Qt::MetaModifier, text: "." }, :next_buffer]
    ]

    aliases.each do |payload, expected_type|
      key = translator.translate(payload)

      expect(router.route(key)).to eq(editor_command(expected_type))
    end
  end

  it "routes all documented Alt+Super editor actions" do
    modifiers = Qt::AltModifier | Qt::MetaModifier
    aliases = [
      [{ key: Qt::Key_B, modifiers:, text: "b" }, "insert-binding-irb"],
      [{ key: Qt::Key_D, modifiers:, text: "d" }, "insert-current-date-time"],
      [{ key: Qt::Key_T, modifiers:, text: "t" }, "insert-current-time"],
      [{ key: Qt::Key_U, modifiers:, text: "u" }, "untabify"],
      [{ key: Qt::Key_Tab, modifiers:, text: "\t" }, "tabify"]
    ]

    aliases.each do |payload, command_name|
      key = translator.translate(payload)

      expect(router.route(key)).to eq(editor_command(:custom_command, { name: command_name }))
    end

    select_line = translator.translate(key: "l".ord, modifiers: Qt::MetaModifier, text: "l")
    expect(router.route(select_line)).to eq(
      editor_command(:custom_command, { name: "select-current-line" })
    )
  end

  it "keeps Alt and Super distinct and preserves Ctrl+Shift punctuation" do
    alt = translator.translate(key: Qt::Key_J, modifiers: Qt::AltModifier, text: "j")
    super_key = translator.translate(key: Qt::Key_J, modifiers: Qt::MetaModifier, text: "j")
    combined = translator.translate(
      key: Qt::Key_Less,
      modifiers: Qt::ControlModifier | Qt::ShiftModifier,
      text: "<"
    )

    expect([alt, super_key, combined]).to eq(["M-j", "s-j", "C-<"])
    expect(router.route(combined)).to eq(editor_command(:previous_buffer))
  end

  it "routes the configured next-buffer Ctrl+greater alias" do
    key = translator.translate(
      key: Qt::Key_Greater,
      modifiers: Qt::ControlModifier | Qt::ShiftModifier,
      text: ">"
    )

    expect(key).to eq("C->")
    expect(router.route(key)).to eq(editor_command(:next_buffer))
  end

  it "routes user-configured mixed-modifier key combinations" do
    original_config_home = ENV.fetch("XDG_CONFIG_HOME", nil)
    Dir.mktmpdir("roded-qt-keymap") do |directory|
      config_directory = File.join(directory, "roded")
      FileUtils.mkdir_p(config_directory)
      File.write(
        File.join(config_directory, "keymap.yml"),
        "M-s-q:\n  type: custom_command\n  payload:\n    name: insert-binding-irb\n"
      )
      ENV["XDG_CONFIG_HOME"] = directory
      application = Roded::Application.new
      application.startup
      frontend_router = Roded::Frontends::QtInputRouter.new(
        application,
        translator,
        Roded::Frontends::QtClipboardBridge.new,
        :qt
      )
      payload = {
        key: Qt::Key_Q,
        modifiers: Qt::AltModifier | Qt::MetaModifier,
        text: "q",
        window_id: application.current_window.object_id
      }

      frontend_router.enqueue_key(payload)
      application.handle_event(application.instance_variable_get(:@event_queue).pop)

      expect(application.current_buffer.to_s).to eq("\nbinding.irb")
    end
  ensure
    original_config_home ? ENV["XDG_CONFIG_HOME"] = original_config_home : ENV.delete("XDG_CONFIG_HOME")
  end

  it "routes Qt Menu and Alt+Menu to the project and buffer pickers" do
    menu = translator.translate(key: Qt::Key_Menu, modifiers: 0, text: "")
    alt_menu = translator.translate(key: Qt::Key_Menu, modifiers: Qt::AltModifier, text: "")

    expect(router.route(menu)).to eq(editor_command(:project_files))
    expect(router.route(alt_menu)).to eq(editor_command(:switch_buffer))
  end

  it "routes Qt Ctrl+@ to the same mark command as Ctrl+Space" do
    ctrl_at = translator.translate(
      key: Qt::Key_At,
      modifiers: Qt::ControlModifier | Qt::ShiftModifier,
      text: "@"
    )

    expect(ctrl_at).to eq("C-@")
    expect(router.route(ctrl_at)).to eq(editor_command(:set_mark))
  end

  it "applies an Alt+Super key payload through Qt input routing into the core" do
    application = Roded::Application.new
    application.startup
    frontend_router = Roded::Frontends::QtInputRouter.new(
      application,
      translator,
      Roded::Frontends::QtClipboardBridge.new,
      :qt
    )
    payload = {
      key: Qt::Key_B,
      modifiers: Qt::AltModifier | Qt::MetaModifier,
      text: "b",
      window_id: application.current_window.object_id
    }

    frontend_router.enqueue_key(payload)
    application.handle_event(application.instance_variable_get(:@event_queue).pop)

    expect(application.current_buffer.to_s).to eq("\nbinding.irb")
  end

  def editor_command(type, payload = {})
    Roded::EditorCommand.new(type, payload, nil, nil)
  end

  it "routes real Qt resize events back to the core" do
    events = []
    application = Object.new
    application.define_singleton_method(:push_event) { |event| events << event }
    view = Roded::Frontends::QtEditorWindow.new
    frontend_router = Roded::Frontends::QtInputRouter.new(
      application, translator, Roded::Frontends::QtClipboardBridge.new, :qt
    )
    frontend_router.connect(view)
    view.show
    view.window.resize(540, 360)
    QApplication.process_events

    expect(events.map(&:type)).to include(:resize)
  ensure
    view&.close
  end

  it "sends Qt wheel movement to the core viewport with its source and window" do
    events = []
    application = Object.new
    application.define_singleton_method(:push_event) { |event| events << event }
    frontend_router = Roded::Frontends::QtInputRouter.new(
      application, translator, Roded::Frontends::QtClipboardBridge.new, :qt
    )

    expect(frontend_router.enqueue_wheel(angle_delta_y: 120, pixel_delta_y: 0, window_id: 42)).to eq(:consume)

    expect(events).to eq([
                           Roded::Event.new(:scroll_by, { amount: -3, source_id: :qt, window_id: 42 })
                         ])
  end

  it "routes Super arrow resizing through the Qt input adapter into core layout" do
    application = Roded::Application.new
    application.startup
    frontend_router = Roded::Frontends::QtInputRouter.new(
      application, translator, Roded::Frontends::QtClipboardBridge.new, :qt
    )
    application.handle_event(Roded::Event.new(:split_vertical, {}))
    payload = {
      key: Qt::Key_Right,
      modifiers: Qt::MetaModifier,
      text: "",
      window_id: application.current_window.object_id
    }

    frontend_router.enqueue_key(payload)
    application.handle_event(application.instance_variable_get(:@event_queue).pop)

    expect(application.editor_snapshot[:tree][:ratio]).to eq(0.45)
  end
end
# rubocop:enable Metrics/BlockLength
