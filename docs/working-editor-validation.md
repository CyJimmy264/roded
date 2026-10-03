# Проверки первой рабочей версии Roded

Этот журнал содержит воспроизводимые результаты текущей ветки. Исторический
отчёт ревизии остаётся в `architecture-review-2026-10-03.md`.

## 2026-10-03 — curses navigation, pane bounds и resize

- `C-n` / `C-p` посылали legacy `:move_cursor` hint до authoritative layout
  snapshot. Curses выполнял старый full-screen redraw через весь `maxy`, мог
  сдвигать содержимое, перезаписывать modeline и показывать строку за границей
  окна. Теперь curses игнорирует устаревший hint; snapshot обновляет только
  затронутые строки через `CursesCursorRedraw`.
- RSpec проверяет, что cursor hint не скроллит и не очищает экран; после
  уменьшения высоты render помещает текст до modeline, а modeline на
  предпоследнюю строку. Curses specs: **3 examples, 0 failures**; RuboCop для
  новых specs: **0 offenses**.
- Настоящий `xterm-256color` PTY, 24×80: два `C-n` дали столько же full-screen
  clears, сколько контрольный запуск без навигации (**5** с учётом startup и
  shutdown); оба процесса завершились с кодом **0**. Второй PTY изменил размер
  до 8×50, отправил `SIGWINCH`, выполнил два `C-n` и `C-x C-c`: resize event
  принят, exit code **0**. Проверки не использовали desktop display.

## 2026-10-03 — Qt пустые строки и block caret

- HTML renderer создаёт видимые paragraph cells для пустых строк, а
  `QtCursorMapper` учитывает эти render-only cells при переводе между core и
  UTF-16 offsets. Regression specs проверяют пустой scratch, пустую строку,
  trailing newline, caret mapping и сохранение пустой строки в Qt document.
- `script/qt_live_smoke.sh` на изолированном Xvfb кликает по пустой третьей
  строке файла; log подтверждает core point `(row 2, col 0)`. Screenshot
  `/tmp/roded-qt-live-smoke.c9zjkq/after-blank-line-caret.png` показывает
  сохранённую пустую строку, подсвеченный фон и видимый синий block caret;
  modeline показывает `3:1`. Тот же smoke повторно запускает настоящий
  `bin/roded --frontend qt` без аргументов: создан `*scratch*`, окно снято в
  `/tmp/roded-qt-live-smoke.kaEpsG/empty-scratch.png`, `C-x C-c` завершил
  процесс с кодом **0**. Qt editor/mouse targeted specs и общий suite проходят.
- Оставшееся расхождение перед Qt/curses parity: один final newline (`a\n`)
  сейчас создаёт видимый пустой paragraph в Qt, а curses рисует только core
  line. В core final newline хранится отдельно, а второй newline (`a\n\n`)
  создаёт явную пустую строку. Нужно выбрать единое поведение и согласовать
  cursor/edit semantics до отметки этого acceptance пункта.

## 2026-10-03 — переход на qt 0.2.0

- Gemfile/gemspec и lockfile обновлены на `qt ~> 0.2.0`. Использованы новые
  generated enum constants, QClipboard text API, native close `:reject`,
  QTextCursor UTF-16 setter и QSplitter sizes; транспортный editor, cursor
  marker и QtCloseGuard удалены. Workaround status обновлён в
  `docs/qt-workarounds.md`.
- Версии: Ruby **3.4.2**, qt **0.2.0**, Qt Widgets **6.11.2**. Runtime API probe
  подтвердил `QTextEdit::NoWrap`, `QTextCursor#position/#set_position`,
  `QClipboard#text/#set_text`, `QSplitter#sizes/#set_sizes`.
- `bundle exec rspec`: **229 examples, 0 failures**. Qt editor/clipboard/close
  offscreen specs: **21 examples, 0 failures**. Targeted RuboCop: **11 files,
  0 offenses**; shell syntax and `git diff --check` прошли. `bundle exec rake`
  также завершает specs успешно, но общий lint gate пока сообщает **55 прежних
  offenses** в `buffer.rb` и curses frontend.
- `script/qt_live_smoke.sh` прошёл под изолированным Xvfb: настоящий Qt frontend
  обработал `C-n`, ввод/сохранение, wheel, `M->`, split, `s-Right`/`s-Left` и
  завершился штатно через `C-x C-c`. Log: `/tmp/roded-qt-live-smoke.dkXtdu/roded.log`;
  снимки сохранены рядом. Это подтверждает X11 synthetic delivery, но не
  физические Super keys. Native close rejection проверен отдельно на реальном
  offscreen QWidget; desktop save/discard/cancel flow ещё остаётся в acceptance.

## 2026-10-03 — Unicode offsets Ruby syntax spans

- `Ripper.lex` отдаёт byte columns, тогда как snapshots и curses/Qt rendering
  адресуют символы. `RubySyntaxTokenizer` теперь конвертирует byte offset начала
  токена в Unicode character column до построения span.
- Specs покрывают число после emoji, незакрытую многострочную строку с кириллицей,
  обновление spans после edit/undo и отсутствие изменений текста, point, истории
  и modified state при получении snapshot.
- Проверки: `bundle exec rspec spec/syntax_highlighter_spec.rb
  spec/syntax_snapshot_spec.rb` — **9 examples, 0 failures**; полный suite
  проверен отдельно в текущей среде.
- Это подтверждает core character offsets; UTF-16 offsets внутри Qt document и
  curses region/search colors остаются открытыми.

## 2026-10-03 — curses token colors в настоящем PTY

- Запуск: `bundle exec bin/roded /tmp/roded-curses-colors.rb` в PTY 24×80,
  `TERM=xterm-256color`, Ruby 3.4.2; файл содержит Ruby keyword, число и comment.
  Ввод `C-x 3` вызывал split и полный snapshot render, затем `C-x C-c` завершал
  приложение с exit code 0. Тогда single-window startup ещё не публиковал layout;
  это исправлено и повторно проверено в последнем этапе 7 ниже.
- Захваченный xterm output содержит SGR `35m` (keyword), `33m` (number) и `37m`
  (comment), а также reverse-video modeline; curses восстановил terminal при
  выходе. Smoke обнаружил, что binding передаёт аргумент в block у `attron`,
  который вызывал `ArgumentError` для строгого lambda; заменён на обычный proc.
  Новый spec воспроизводит контракт `attron` и проходит.
- Остаются проверками region/search colors, monochrome fallback и физические
  curses сценарии с paste/resize.

## 2026-10-03 — Qt caret и Unicode grapheme offsets

- Runtime probe на qt 0.1.9 / Qt Widgets 6.11.2 показывает, что Qt `Right`
  перемещает presentation caret по графемам, тогда как core хранит codepoint
  columns. `QTextEdit` binding не предоставляет `textCursor`/`setTextCursor`,
  поэтому exact UTF-16 position setter недоступен.
- Добавлен `QtCursorMapper`: он считает полные grapheme boundaries до core point
  и размещает Qt caret по visual movement. Реальный offscreen widget проверяет
  следующую копируемую позицию для astral emoji, combining sequence и ZWJ family.
- Команда: `GEM_HOME=/tmp/roded-qt-gems
  GEM_PATH=/home/mveynberg/.rbenv/versions/3.4.2/lib/ruby/gems/3.4.0:/tmp/roded-qt-gems
  XDG_CONFIG_HOME=/tmp/roded-qt-spec-config QT_QPA_PLATFORM=offscreen
  bundle exec rspec spec/qt_editor_window_spec.rb` — **4 examples, 0 failures**.
- Ограничение зафиксировано в `qt-workarounds.md`: точка внутри графемы
  отображается на предыдущей caret boundary; точная UTF-16 установка и mouse
  mapping остаются открытыми.
- Полный запуск через `bundle exec rake` после этой проверки: **163 examples,
  0 failures**; общий RuboCop gate пока сообщает **91 offense**.

## 2026-10-03 — describe-bindings в curses и через M-x

- `C-h b` открывает read-only `*Bindings*` с текущими keymap entries и
  зарегистрированными M-x commands. `M-x describe-bindings` обновляет тот же
  buffer. Integration spec добавляет пользовательскую `M-q` binding и command,
  проверяет их отображение и фактический запуск.
- Curses decoder различает byte `C-h` (`0x08`) и Backspace (`DEL`, `0x7f`),
  поэтому стандартная terminal sequence не теряется как Backspace.
- Настоящий curses PTY smoke: Ruby 3.4.2, `TERM=xterm-256color`, размер 24×80;
  введены `C-h b`, `M->`, `C-x C-c`. В captured screen присутствуют help title,
  `C-h b`, `describe-bindings`; exit code **0**, terminal восстановлен.
- `spec/help_operations_spec.rb` и `spec/curses_input_decoder_spec.rb`:
  **5 examples, 0 failures**. Реальные curses/Qt help scroll+resize и остальные
  picker providers остаются открытыми.
- После включения help и исправления ожидания M-x visible page полный suite:
  **164 examples, 0 failures**; после извлечения таблицы default key bindings
  повторный `bundle exec rake` подтвердил **164 examples, 0 failures** и
  **88 RuboCop offenses** (все gate-нарушения находятся в существующем lint debt).

## 2026-10-03 — валидация пользовательского keymap

- YAML keymap теперь проверяется целиком: корневой mapping, непустые
  последовательности с одиночными пробелами между chords, mapping для каждой
  записи, известный event type и mapping для payload. Некорректный файл
  безопасно заменяется defaults, а frontend при старте показывает путь и причину.
- Проверены валидная пользовательская привязка, некорректный YAML, неизвестный
  type и доставка предупреждения в frontend. Prefix hints и custom command
  остаются на общем router/registry пути и имеют integration coverage.
- Targeted RSpec: **74 examples, 0 failures**; RuboCop на четырёх изменённых
  implementation/spec files: **0 offenses**.
- После изменения полный `bundle exec rake`: **168 examples, 0 failures**;
  общий RuboCop gate всё ещё падает на **88 offenses в 96 files**.

## 2026-10-03 — multi-file curses acceptance через PTY

- Команда: `bundle exec bin/roded <first.rb>` в PTY 24×80 с
  `TERM=xterm-256color`, Ruby 3.4.2, Qt/ffi gems из `/tmp/roded-qt-gems` и
  логом `/tmp/roded-curses-accept.log`.
- Через реальный curses input выполнены `C-x 3`, `C-x C-f <second.rb>`, ввод
  `B`, `C-x C-s`, `C-x C-c`. Процесс завершился с кодом **0**, второй файл
  сохранён как `Bsecond = true\n`; терминальная сессия выдала 12 132 bytes.
- Проверка прошла в изолированном PTY; desktop display и xdotool не использовались.

## 2026-10-03 — Tab и indent-region

- Curses нормализует terminal Tab в общий binding `Tab`; он и `M-x indent-region`
  вставляют два пробела. При выделении indent добавляется к каждой строке
  region одним undo group; после edits сохраняются преобразованные point/mark.
- Specs проверяют текущую строку, многострочный region, undo и readonly buffer.
  Targeted RSpec: **19 examples, 0 failures**.
- Настоящий curses PTY (`TERM=xterm-256color`, 24×80): нажат Tab добавило
  два пробела в `tab.rb`, `C-x C-s` сохранил результат, `C-x C-c` завершил
  процесс с кодом **0**. Ruby 3.4.2, Qt/ffi gems из `/tmp/roded-qt-gems`.
- Полный прогон после изменения: **171 examples, 0 failures**; RuboCop всё ещё
  сообщает **88 offenses в 97 files**, тот же общий debt count.

## 2026-10-03 — Qt Super payload routing

- Отдельный spec использует enum constants установленного Qt 6.11.2 и поля
  `key`, `modifiers`, `text` из generated `QKeyEvent` payload schema. Он
  прогоняет `M-s-j/k/c`, `s-w`, `s-Left/Right`, `s-,/.` через реальный
  `QtKeyTranslator` и общий `CommandRouter`; проверяет различие Alt/Super и
  Ctrl+Shift punctuation. Это проверка runtime constants/translation/routing,
  не фактической доставки desktop keyboard events.
- Targeted specs: **5 examples, 0 failures**; RuboCop на новом spec чистый.
  Полный `bundle exec rake`: **173 examples, 0 failures**, затем общий RuboCop
  gate сообщает **88 offenses в 98 files**. Physical Super keys и остальные
  незакрытые Qt UI flows остаются обязательными.

## 2026-10-03 — personal text commands и сквозной Qt input route

- Реализованы и зарегистрированы `select-current-line`, `tabify`, `untabify`,
  `insert-current-date-time`, `insert-current-time`, `insert-binding-irb`, а
  также M-x aliases для viewport scrolling и split resizing. Leader bindings
  `C-c d d/t`, `C-c l`, `C-c r b`, плюс `s-l`, `M-s-u`, `M-s-Tab`, `M-s-d/t/b`
  вызывают те же registry actions.
- `C-@` транслируется в Qt как отдельный input token и ведёт в mark command;
  curses NUL остаётся alias `C-SPC`. Qt `Menu`/`M-Menu` ведут к project/buffer
  pickers. `C-x <left>/<right>` добавлены как aliases к переключению buffers.
- `tabify`/`untabify` применяют tab width **2** к пробельным группам по всему
  выбранному тексту или buffer. Все views сохраняют соответствующий character
  point/mark; операция одной undo group. Commands не меняют readonly buffer.
- Specs: line selection, tab conversion/undo, local date/time formats,
  `binding.irb` indentation, readonly guards, Qt Menu/Ctrl+@ and shortcut routes.
  Настоящий `QtInputRouter` + Qt clipboard widget получил QKeyEvent-shaped
  `M-s-b` payload и изменил core buffer до `\nbinding.irb`.
- Curses PTY (`TERM=xterm-256color`, 24×80, Ruby 3.4.2): после сигнала готовности
  input mode выполнена последовательность `C-c d d`, затем save/quit; файл
  содержит `03/10/2026 13:52:54`, процесс завершился с кодом **0**.
- Полный `bundle exec rake`: **185 examples, 0 failures**; общий RuboCop gate
  остаётся **88 offenses в 101 file**. Новые text/Qt shortcut files проходят
  targeted RuboCop без offenses. Физические Super keys и Qt desktop acceptance
  не проверялись в этом этапе.

## 2026-10-03 — Qt clipboard paste через общий core event

- Runtime probe qt 0.1.9 / Qt Widgets 6.11.2: `QApplication.clipboard`
  возвращает QObject без `text`/`set_text`; `QTextEdit` предоставляет реальные
  `paste`, `copy`, `can_paste`, `set_plain_text` и `to_plain_text` методы.
- Добавлен transport-only `QTextEdit` workaround. На настоящем Qt Widgets
  offscreen он round-trip-ит `alpha\nвторой 🙂` через clipboard. Qt callback для
  `C-S-v` посылает ровно один `Event(:paste)` с UTF-8 payload, `source_id: :qt`
  и id активного окна. `C-v` остаётся page-down.
- Команда: `GEM_HOME=/tmp/roded-qt-gems GEM_PATH=/home/mveynberg/.rbenv/versions/3.4.2/lib/ruby/gems/3.4.0:/tmp/roded-qt-gems QT_QPA_PLATFORM=offscreen XDG_CONFIG_HOME=/tmp/roded-qt-spec-config bundle exec rspec spec/qt_clipboard_bridge_spec.rb spec/qt_key_translator_spec.rb`
  — **5 примеров, 0 failures**.
- Полный `rspec` на Qt offscreen: **154 примера, 0 failures**. Он выявил
  namespace collision в splitter (`Qt::Horizontal/Vertical` разрешались в
  frontend class); ссылки исправлены на top-level `::Qt`, split-widget specs
  прошли в полной suite.
- Desktop clipboard smoke и copy/cut через mouse selection остаются открытыми.

## 2026-10-03 — Qt region copy/cut в системный clipboard

- Qt `C-S-c` и `C-S-x` преобразуются в core `M-w` и `C-w`; операции остаются
  в общей command path. Core публикует скопированный/вырезанный текст как
  `:clipboard_write`, а Qt записывает его через native widget slot в GUI thread.
- `spec/application_spec.rb` проверяет, что копирование не меняет текст,
  вырезание остаётся undoable и KillRing не объединяет copy с последующим kill.
  Qt bridge spec проверяет mapping desktop shortcuts в core key events.
- Qt UI dispatcher spec проверяет, что core `:clipboard_write` использует
  настоящие Qt widget copy slots. Целевой RuboCop: **9 файлов, 0 offenses**.
- Полное RSpec после изменений: **156 примеров, 0 failures**. Offscreen clipboard
  transport остаётся проверенным; desktop copy/cut с физическим выделением
  мышью не проверялись и остаются открытыми.

## 2026-10-03 — Qt native close cancellation

- На реальном Qt Widgets 6.11.2 offscreen `QWidget.close()` доставил
  `Event(:close_request)` и скрыл окно даже при callback `:consume`. Отдельный
  probe с `:ignore` показал то же закрытие через стандартный `closeEvent`.
- Добавлен `QtCloseGuard`: prompt/message/cancel update восстанавливает тот же
  widget, а accepted `:quit` не открывает его снова.
- `spec/qt_frontend_close_spec.rb` использует настоящий `QWidget.close`, Qt
  event subscription, `QApplication.process_events` и проверяет состояние
  видимости после prompt и cancel.
- Целевой RuboCop: **6 файлов, 0 offenses**. Полное RSpec после изменений:
  **157 примеров, 0 failures**.
- Live desktop close/save/discard/cancel smoke остаётся открытым.

## 2026-10-03 — bracketed paste в настоящем curses TUI

- Curses включает terminal bracketed-paste mode, собирает `ESC[200~` …
  `ESC[201~` в один `Event(:paste)` и сохраняет bytes после закрывающего маркера
  для следующего ввода. Фрагментированный start marker также покрыт spec.
- `spec/curses_input_decoder_spec.rb`: 4 примера, 0 failures; decoder/spec
  проходят RuboCop без offenses. Настоящий PTY
  (`TERM=xterm-256color`, 24×80, Ruby 3.4.2) вставил `alpha\nвторой` через
  bracketed-paste sequence, сохранил файл через `C-x C-s` и завершил curses
  через `C-x C-c`; exit code 0, сохранён точный UTF-8 текст без final newline.
- Полный RSpec после выделения decoder: **152 примера, 0 failures**.
- На момент этого этапа Qt clipboard paste ещё не была направлена в core
  `:paste` contract; последующая проверка и интеграция записаны выше.

## 2026-10-03 — Unicode position transforms между views

- Добавлен end-to-end core scenario с греческой буквой, emoji вне BMP и
  combining mark: insertion между code points корректирует point/mark второго
  view, а undo/redo возвращают позиции на правильные Unicode границы.
- Проверяется вместе с существующим сценарием ASCII edits в двух views.
  `spec/application_spec.rb`: 58 примеров, 0 failures.
- Сверил Qt test approach с локальным qtimetrap: его integration specs создают
  реальные widgets, прокачивают Qt event loop через `QApplication.process_events`
  и проверяют видимое состояние после действия; этот паттерн оставляю для
  дальнейшей Qt parity проверки.

## 2026-10-03 — reload после внешнего изменения файла

- При конфликте сохранения доступны reload, overwrite и cancel. Reload сначала
  полностью читает и проверяет внешний файл, затем обновляет buffer, revision и
  позиции views. Если чтение не удалось, локальные edits остаются нетронутыми.
  Во время save-before-quit успешный reload продолжает закрытие после очистки
  modified state.
- Полный RSpec: **148 примеров, 0 failures**, включая проверку сохранения
  локальных edits при отказе reload из-за binary данных. `file_operations.rb` и
  `file_reload_operations.rb` проходят RuboCop.
- Полный `bundle exec rake` пока падает на оставшихся проектных RuboCop offenses;
  требуется отдельная работа над линтером и повторная полная проверка.

## 2026-10-03 — этап 1: lifecycle и точность базового file roundtrip

### Автоматические проверки

- `bundle exec rspec`: **40 examples, 0 failures**.
- Specs проверяют завершение event loop через `C-x C-c` и `M-x quit`, сигнал
  при фокусе minibuffer, EOF, исключение во время обработки события, закрытие
  frontend и восстановление завершения процесса; ошибки чтения/записи;
  редактирование пустого файла; LF, CRLF, UTF-8, mixed-ending отказ и final
  newline.
- `bundle exec rubocop --format simple`: **68 offenses**. Начальный baseline из
  ревизии был 70; lint не отключался. `bundle exec rake` пока завершает specs
  успешно, но падает на существующих и оставшихся offenses. Требование получить
  зелёный rake сохраняется для завершающего этапа.

### Настоящий curses smoke test

- Запуск: `bundle exec bin/roded` в pseudo-terminal 24×80 с `TERM=xterm-256color`
  и `RODED_LOG_PATH=/tmp/roded-pty.log`.
- Переданы реальные terminal key bytes `C-x`, `C-c` после отрисовки welcome.
- Результат: welcome отображён curses, приложение завершилось с exit code 0,
  terminal alternate screen восстановлен.
- Среда: Ruby 3.4.2, Linux, `DISPLAY=:0`; пользовательская оболочка сообщает
  `TERM=dumb`, поэтому для smoke test задан совместимый xterm TERM. Без явного
  `RODED_LOG_PATH` sandbox не дал создать файл в пользовательском cache;
  повторный запуск с логом в `/tmp` прошёл.

### Qt этап 3: первый рабочий desktop adapter

- `bundle exec rspec`: **48 examples, 0 failures**. Добавлены тесты преобразования
  Qt payload в `C-`, `M-` и `s-` key names, в том числе для сочетаний и
  пунктуации.
- Реальный Qt Widgets 6.11.2 desktop smoke прошёл на X display `:0` с gem
  `qt` 0.1.9 под установленным Ruby 4.0.5: окно приняло ввод, `Super+j` и
  `Alt+Super+comma` дошли как `s-j` и `M-s-,`, команды отработали, `C-x C-c`
  штатно завершил приложение. Ввод отправлял XTest/xdotool, то есть это
  синтетические X11 events, а не физическое нажатие клавиатуры.
- Smoke запускался отдельным процессом с временным `XDG_CONFIG_HOME`, чтобы
  Qt не пытался записывать настройки в домашний каталог. Приложение задаёт
  стабильное имя `roded` для QApplication и само не вызывает API звука.
- Установлен `qt` 0.1.9 на pinned Ruby 3.4.2; Bundler разрешает зависимость без
  локального пути. Под `QT_QPA_PLATFORM=offscreen` настоящий Qt
  `QPlainTextEdit` создался. `bin/roded --frontend qt` поднял CLI event loop;
  этот запуск остановлен таймаутом, так как offscreen окно не получает ввода.
- Qt frontend выбирается командой `bin/roded --frontend qt`. Полная проверка
  физической Super-клавиши, мыши, выделения и clipboard остаётся открытой до
  этапа 9.

### Ограничения этапа

File save здесь сохраняет текстовое представление, но ещё не использует
безопасную атомарную замену, revision tracking или conflict prompts. Эти сценарии
остаются открытыми до этапа 4.

## 2026-10-03 — этап 4, подэтап: безопасный FileService

- Добавлен FileService с UTF-8/binary/line-ending validation, нормализацией
  существующих путей и immutable file revision.
- Save пишет временный файл в том же каталоге, сохраняет mode, fsync-ит данные
  и атомарно переименовывает. Переход по symlink обновляет target, сохраняя
  ссылку. Отсутствующие parent directories автоматически не создаются.
- Save обнаруживает revision conflict и оставляет внешнее содержимое на диске
  вместе с текущим текстом buffer. UI пока сообщает об отказе; выбора
  reload/overwrite/cancel и modified-state модели ещё нет.
- Автоматические проверки: **54 examples, 0 failures**; RuboCop на новых
  FileService и spec: **0 offenses**.
- Buffer сравнивает текст с последним успешным saved snapshot: открытие и
  успешное сохранение сбрасывают modified state, возврат edits к сохранённому
  тексту снова делает buffer чистым. Ошибки и conflict не сбрасывают modified.
- Проверки теперь: **56 examples, 0 failures**. Save/discard/cancel prompts и
  undo до saved state ещё предстоит реализовать.

## 2026-10-03 — запуск документов

- CLI передаёт все пути в startup, открывает каждый buffer и выбирает последний
  в первом окне. При пустом списке создаётся writable `*scratch*`; открытие
  нового пути создаёт пустой file buffer без создания каталогов.
- Существующий файл открывается повторно через symlink/путь alias в уже
  существующий buffer. Для новой удалённой цели save проверяет, что файл не
  появился на диске после открытия.
- Проверки: **60 examples, 0 failures**. Реальный многодокументный curses/Qt
  сценарий с переключением buffer ещё не выполнен: переключение будет в этапе 5.

## 2026-10-03 — переключение buffers

- Реализованы `C-x b` по точному имени/пути, `C-x C-Left/Right` для циклического
  переключения, `C-x k` для закрытия чистого buffer. При закрытии последнего
  документа остаётся редактируемый `*scratch*`; изменения в dirty buffer пока
  блокируют закрытие с сообщением.
- Добавлены проверки CLI-документов, переключения по key sequences и kill
  поведение: **63 examples, 0 failures**.
- Buffer picker с completion/preview и предложением save/discard/cancel,
  disambiguation совпадающих basename и полноценное multipane UI остаются этапом 5/6.
- Настоящий curses PTY с двумя CLI-файлами показал второй документ; `C-x b` с
  путём первого файла переключил экран на него. `C-x C-c` завершил процесс с
  exit 0 и восстановил alternate screen. Полный acceptance edit/save/split ещё
  не выполнен.

## 2026-10-03 — save/close prompts

- `C-x C-s` для unnamed buffer запрашивает путь; `C-x C-w` вызывает Save As.
  Существующая цель требует yes/no подтверждение, внешняя revision conflict
  требует подтверждение overwrite, отмена сохраняет buffer и файл без изменений.
- `C-x C-c`, `M-x quit`, Qt close request и `C-x k` предлагают save/discard/cancel
  для dirty buffers. Save проходит по всем изменённым документам, запрашивает
  путь для unnamed buffer и не закрывает редактор, если запись отклонена.
  Сигналы/EOF завершают процесс без интерактивного ожидания.
- Проверки: **74 examples, 0 failures**. Не реализовано повторное чтение disk
  version из conflict prompt; доступен overwrite или cancel.
- File open/save, overwrite confirmation и dirty-close state вынесены из
  `Application` в отдельные workflow modules; completed minibuffer actions
  проходят через отдельный handler. Их specs остались зелёными, новые workflow
  files проходят RuboCop без offenses.

## 2026-10-03 — базовая edit history

- Buffer сохраняет локальные line deltas и cursor/line-ending metadata для
  insert, backspace, delete, newline и kill-line; реализованы undo, redo и
  вложенно безопасная группировка изменений. Новая правка очищает redo history.
- `M-x undo` и `M-x redo` применяются к активному buffer; keymap также содержит
  `C-/`, `C-_`, `C-x u` и `C-c r d`.
- Проверки: **79 examples, 0 failures**. Unicode insert, LF/CRLF/final newline,
  undo до clean saved state, redo, группировка и readonly buffer покрыты specs.
- Полные region/kill-ring transactions, paste grouping, все изменяющие entry
  points и синхронизация независимых views остаются открытыми. Stage 4 не завершён.
- RuboCop ещё не зелёный: изменённые Buffer/Application/CommandHandler содержат
  metric/style offenses; они остаются в текущем общем lint debt и будут устранены
  при завершении соответствующих core модулей.

## 2026-10-03 — multiline paste в core

- Добавлены `Buffer#insert_text` для нормализованного UTF-8 текста с переводами
  строк и routed `Event(:paste)`. Вставка в середине строки сохраняет обе части
  исходной строки и создаёт одну undo-операцию.
- Проверки: **82 examples, 0 failures**; полный RSpec и `git diff --check` прошли.
  Прямой RuboCop Buffer/spec обнаруживает 16 legacy metric/style offenses в
  Buffer; новые paste helpers не добавили отдельных offenses. Полный lint остаётся
  незелёным.
- Событие пока не порождается curses bracketed paste или Qt clipboard; это
  потребуется проверить в настоящих frontend до завершения этапов 5 и 9.

## 2026-10-03 — C-k и последовательные kill-команды

- `C-k` на конце строки теперь удаляет line break и кладёт `\n` в KillRing;
  при наличии final newline он также удаляется. Повторные kill-команды
  склеиваются в новую верхнюю запись, а любая другая core-команда завершает
  последовательность.
- Undo восстанавливает удалённый separator/final newline. Проверки: **86
  examples, 0 failures**. `bundle exec rubocop lib/roded/kill_ring.rb
  spec/kill_ring_spec.rb`: без offenses; `git diff --check` чистый.
- C-w/M-w/C-y, выбор KillRing через picker и region state в окне ещё не
  реализованы; весь edit-model этап остаётся открытым.

## 2026-10-03 — модель позиции окна

- `Window` теперь хранит собственные point, mark, top line и left column, а
  также запоминает позиции при переключении buffers. Application использует
  point активного окна для routed edits; `Buffer#cursor_pos` пока остаётся
  временным совместимым зеркалом для текущего однопанельного UI.
- Проверки: **91 examples, 0 failures**. Specs покрывают две модели view на
  общем buffer, независимые point/mark, clamp и восстановление позиции после
  buffer switching. RuboCop по `window.rb` и `window_spec.rb` чистый.
- На момент того среза окна ещё не отображались; это было закрыто последующим
  этапом split windows ниже. Этапы 2 и 5 в целом остаются открытыми.

## 2026-10-03 — split windows и UI-проверка

- Добавлены вложенное дерево окон и команды `C-x 2`, `C-x 3`, `C-x o`,
  `C-x 0`, `C-x 1`; curses показывает split panes, отдельные modelines и
  общее содержимое одного buffer. Другие views получают преобразование
  point/mark при edit и undo.
- В реальном PTY (`TERM=xterm-256color`, 24×80, Ruby 3.4.2) выполнены split,
  переход во второе окно, вставка `A`, переход обратно, undo и quit. Процесс
  завершился с exit code 0 и восстановил alternate screen. Предыдущие PTY
  прогоны этого этапа также проверили `C-x 3` и `C-x 0`.
- `QT_QPA_PLATFORM=offscreen bundle exec rspec spec/qt_editor_window_spec.rb`
  создал реальные `QPlainTextEdit` и `QSplitter`, проверил два child pane и
  collapse после удаления окна. Desktop Qt запущен с gem `qt` 0.1.9 на X11
  (`DISPLAY=:0`); XTest/xdotool доставил `C-x` и `2` в core. На снимке desktop
  разделение pane не удалось подтвердить визуально, поэтому Qt layout smoke
  остаётся открытым.
- В том же desktop-сеансе Super-комбинации не появились в журнале Qt key events;
  вероятен перехват оконным менеджером. Проверка Super на физической клавиатуре
  остаётся открытой. Позднее обнаружен desktop smoke-скрипт
  `/tmp/roded_qt_smoke.rb`, запускавшийся под `DISPLAY=:0`. Пользовательское
  предупреждение с заголовком `roded_qt_smoke.rb` и путём
  `~/.config/roded_qt_smoke.rbrc` похоже на попытку этого процесса записать
  config вне writable roots sandbox. Причинность не доказана; xdotool напрямую
  не вызывает sound API, но его ввод мог активировать приложение/оконный менеджер,
  поэтому нельзя исключить связь с увиденной модалкой или звуком.
- Keymap теперь маршрутизирует доступные aliases `M-s-j`, `M-s-k`, `M-s-c`,
  `s-w`, `s-,`, `s-.`, `C-<` и `C->` к существующим save/buffer/window
  действиям. Specs проверяют фактический результат CommandRouter; это не
  заменяет runtime-проверку физической Super-клавиши.
- Полный набор RSpec: **99 examples, 0 failures**. RuboCop новых Qt pane/splitter
  компонентов: **0 offenses**. Общий RuboCop по-прежнему падает на накопленном
  долге; `bundle exec rake` пока не проходит.

## 2026-10-03 — region, cut/copy/yank

- Добавлены `C-SPC`, `C-w`, `M-w`, `C-y`; выбор текста удаляется одной
  undo-операцией, KillRing хранит удалённый текст, readonly buffer отклоняет
  region delete. Buffer extraction/deletion сохраняет UTF-8 и CRLF.
- Curses нормализует terminal NUL в `C-SPC`; живой PTY (`TERM=xterm-256color`)
  подтвердил ввод `abc`, установку mark, выделение движением, `C-w`, `C-y` и
  возврат текста к `abc`. Закрытие dirty scratch прошло через discard prompt,
  процесс завершился с exit code 0 и вернул terminal mode.
- Qt pane теперь использует `QTextEdit` read-only presentation и формирует HTML
  selection из immutable core snapshot. Runtime probe gem 0.1.9 подтвердил
  `QTextEdit#set_html`; offscreen Qt test проверяет escaping, сохранение текста
  и выделение региона. Mouse-driven selection/clipboard в desktop UI ещё не
  проверены.
- Полный RSpec: **105 examples, 0 failures**. Новые core/curses изменения пока
  увеличили RuboCop debt; общий `bundle exec rake` остаётся красным.

## 2026-10-03 — immutable snapshots для document/view state

- `Buffer#lines`, `#cursor_pos`, `#line_at_cursor` и `Window#point/#mark`
  отдают замороженные копии. Внешний читатель больше не может менять живой
  текст или позицию без edit API. Specs проверяют freeze и отсутствие обходного
  изменения документа.
- Полный RSpec после изменений: **106 examples, 0 failures**. Требования к
  единому command registry, history encapsulation и single-writer REPL API
  остаются открытыми; этап 2 не завершён.

## 2026-10-03 — yank-pop и курсор после paste

- `M-y` после `C-y` циклически меняет последнюю вставку на следующий KillRing
  элемент; вся замена — одна undo-группа. Любая другая команда аннулирует
  доступность yank-pop. KillRing items теперь возвращаются immutable snapshot.
- Исправлен cursor offset при вставке однострочного текста в середину строки;
  многострочная вставка оставляет point после последнего вставленного символа
  перед исходным суффиксом строки.
- Полный RSpec: **108 examples, 0 failures**. Interactive candidate picker для
  `M-y`, bracketed paste в настоящем curses и общий frontend acceptance остаются
  открытыми.

## 2026-10-03 — навигация, viewport и command registry slice

- Реализованы `M-f/M-b`, `M-</M->`, `M-p/M-n`, `M-P/M-N`. Word movement
  проходит Unicode-слова; scroll обновляет top line, сохраняя point, а размер
  страницы запрашивается у frontend с ID активного view.
- `s-Left/s-Right` теперь меняют ratio side-by-side split; bounds 10–90%
  проверяются на `WindowLayout`, а curses и Qt строят layout по ratio snapshot.
- Введён `CommandRegistry`: M-x и custom key binding могут вызвать одну команду,
  доступна регистрация через Ruby API, command catalog immutable. Существующие
  quit/undo/redo/save/open/buffer клавиши уже делегируют этому реестру; остальным
  командам ещё предстоит перейти на общий контракт.
- Автоматические проверки: **112 examples, 0 failures**. Full lint и живой Qt
  smoke для Super resizing пока не зелёные/не подтверждены.

## 2026-10-03 — command/buffer/KillRing picker

- Введена общая core-модель picker: независимые orderless query terms без
  учёта регистра, стабильный порядок, C-n/C-p, пустой список и immutable UI
  snapshot. Пустой query не исполняет/выбирает случайный первый элемент.
- `M-x` и `C-x b` показывают кандидатов в curses и Qt echo area; `M-y` теперь
  открывает KillRing picker и после выбора заменяет предыдущий yank одной
  undo-группой. Обычные клавиши редактируют query, стрелки/C-n/C-p меняют
  selection, Enter принимает, C-g отменяет.
- Find/save path picker получает tracked и untracked Git пути через
  `git ls-files --exclude-standard`; Git ignores соблюдаются. Вне Git обходятся
  файлы под текущим root с exclusions для `.git`, cache и generated dirs.
- Полный RSpec: **121 examples, 0 failures**. Реальный curses PTY
  (`TERM=xterm-256color`, 24×80) показал список `M-x`, query `q` сузил его до
  `quit`, Enter выполнил команду и процесс завершился с exit code 0. Второй
  PTY сценарий вызвал `C-x C-f`, отфильтровал `GOAL.md`, открыл файл из picker,
  затем штатно вышел; exit code 0.
- Qt offscreen widget проверяет показ query и выбранного candidate. Picker Qt
  пока не прошёл полный desktop acceptance. Project/line-search providers и
  picker resize/scroll ещё не готовы. Полный RuboCop не зелёный; новые picker
  и file-path provider files lint чистые.

## 2026-10-03 — поиск, goto-line и query-replace

- `C-s` открывает строковый picker и Enter перемещает point к совпавшей строке;
  `C-g` закрывает его без перемещения point. Добавлены forward/backward search
  через M-x, `M-g g` и `M-%` с skip, replace, replace-all и cancel. Replace
  обратим через undo, replace-all записывается одной undo-группой.
- Исправлена маршрутизация multi-key Meta prefix: теперь `Esc g g` разрешает
  binding `M-g g` так же, как обычные multi-key prefixes.
- File picker умеет переходить в выбранную директорию и дальше фильтровать её
  содержимое. Git project paths получают `git ls-files` exclusions и доступны
  через `C-c p f`. Поиск, query-replace, and picker logic вынесены из
  Application в общие core operations modules.
- Полный RSpec: **129 examples, 0 failures**. Реальный curses PTY прошёл
  интерактивный `C-s` и `M-%`: после skip/replace-all на экране появился
  `fox dog fox`; quit/discard завершил приложение с exit code 0. Desktop Qt и
  полный RuboCop остаются открытыми проверками.

## 2026-10-03 — syntax modes и token spans

- Filename определяет Ruby, JSON, YAML, Markdown или plain mode; команда
  `M-x set-major-mode` меняет mode без edits. Общий tokenizer возвращает frozen spans;
  Ruby использует Ripper и обрабатывает incomplete/multiline tokens, остальные
  modes дают минимальные полезные категории.
- Qt применяет theme colors к token spans и показывает modified/readonly/mode в
  modeline. Curses рендерит категории через цветовые пары, активный modeline
  отмечается reverse-video; терминал без color support сохраняет текст и
  selection.
- Проверяется, что edits пересчитывают spans, undo возвращает прежние spans, а
  modified state остаётся согласованным. Offscreen Qt проверил HTML color и
  modeline; реальный curses PTY (`xterm-256color`) отрисовал Ruby buffer и
  выдал color escape sequences. Полный RSpec: **136 examples, 0 failures**.
- Новые syntax/tokenizer files проходят RuboCop. Полная интеграция подсветки с
  region/search и отдельная monochrome терминальная проверка ещё не сделаны.

## 2026-10-03 — первый сквозной Ruby REPL slice

- `RubyReplSession` держит один in-process binding, историю и отдельный worker.
  Многострочный код, `puts` / `print`, `$stdout` / `$stderr`, `warn`, exceptions,
  `exit` и `Thread#raise(Interrupt)` возвращают immutable event в core. Историю
  можно листать `C-c C-p` / `C-c C-n`; API наружу выдаёт frozen snapshots и
  направляет edits/команды обратно через core event queue.
- `editor.register_command` добавляет command и optional key binding из REPL.
  Integration spec запускает такую команду через binding и M-x; отдельный тест
  выполняет editor mutation, undo и redo через API и проверяет readonly snapshot.
- Полный RSpec: **146 examples, 0 failures**. Новые REPL/session specs проходят
  RuboCop без offenses.
- Настоящий curses PTY (`TERM=xterm-256color`, Ruby 3.4.2): открыт `*ruby*`,
  введены многострочное выражение (`=> 3`), `puts` / `warn`, ошибка `RuntimeError:
  broken` с последующим успешным `=> 4`, interrupt бесконечного Ruby loop, `exit`
  и выход из изменённого редактора с discard; процесс завершился с exit code 0.
  Qt Widgets 6.11.2 / gem `qt` 0.1.9: offscreen real-widget smoke исполнил через
  REPL core API edit в открытый buffer `target`; `QTextEdit` получил актуальный
  snapshot `qt-repl-visible`. UI pump и event queue были живыми. Тест использовал
  core input events, а не реальные QKeyEvent.
- До этого этапа xdotool уже применялся для synthetic desktop key checks;
  desktop smoke не следует считать изолированным только потому, что команда
  запущена в sandbox. После обнаружения возможной связи новые desktop key
  injections не выполнялись. Источник звука не диагностирован. Реальный desktop
  REPL keyboard smoke остаётся открытым. `STDOUT` constant и произвольные native
  writes не перехватываются.
- Этап 8 подтверждён curses PTY, Qt real-widget offscreen smoke и integration specs.
  Отдельный physical Qt key smoke остаётся в этапе 9 вместе с Super shortcuts;
  direct writes через `STDOUT` constant/native file descriptors ограничены
  особенностями Ruby binding и не входят в перехват `$stdout` / `$stderr`.

## 2026-10-03 — этап 2, подэтап: source routing и загрузка core

- `bundle exec rspec`: **45 examples, 0 failures**.
- Проверены независимые pending prefixes, пользовательская multi-key
  последовательность `C-c r r`, page size источника ввода и подключение
  frontend после открытия документа.
- Свежий процесс с `require "roded"` подтвердил отсутствие загруженного curses;
  `bin/roded` явно загружает curses adapter и завершает pseudo-terminal smoke
  (`TERM=xterm-256color`, 24×80, `C-x C-c`) с exit code 0.
- RuboCop остаётся на **68 offenses**: подэтап не увеличил долг относительно
  этапа 1.
- Page-size выбор учитывает input source; отдельные editor views и их геометрия
  ещё не введены. UI пока не сведён к одному immutable snapshot, поэтому этап 2
  остаётся открытым.

## 2026-10-03 — picker query history и разделение providers

- Picker хранит отдельную историю принятых непустых запросов каждого типа;
  `M-p/M-n` в активном picker листают её, а в buffer сохраняют scroll bindings.
  Возврат вперёд восстанавливает query draft, введённый до просмотра истории.
- Provider API вынесен в отдельный модуль; picker сохраняет live orderless
  filtering и selection snapshot. Specs покрывают Unicode-поиск, историю,
  duplicate suppression, восстановление draft и возврат принятого M-x query.
- Целевые specs: **68 examples, 0 failures**; полный `bundle exec rake`:
  **190 examples, 0 failures**. Полный RuboCop сообщает **87 offenses** в 102
  файлах; 10 файлов модели/providers и specs прошли целевой RuboCop без
  offenses. `command_handler.rb` уже содержит крупные метрики и другие lint
  violations, поэтому в эту чистую выборку не входит.
- `git diff --check` проходит. Provider coverage, line search/replace и
  физическая клавиатура Qt остаются незакрытыми критериями.

## 2026-10-03 — picker viewport и resize в curses/Qt

- Общий `PickerViewport` ограничивает число строк доступной высотой и сохраняет
  выбранный candidate в видимой части. Curses сохраняет место для minibuffer;
  Qt учитывает фактическую высоту echo widget.
- Curses обрабатывает `SIGWINCH`, обновляет curses screen и запрашивает свежий
  snapshot core. Qt resize event также проходит в core и возвращает render
  snapshot в GUI thread.
- Настоящий curses PTY: `TERM=xterm-256color`, 6×80 → 3×80 во время picker,
  прокрутка, cancel и `C-x C-c`; завершение с code 0, без ошибок в выводе.
  `RODED_LOG_PATH` и `XDG_CONFIG_HOME` указывали на `/tmp`, desktop/X11 не
  использовался.
- Qt Widgets **6.11.2**, gem `qt` **0.1.9**, backend **offscreen**: настоящий
  `QWidget` получил resize event; в окне 240×180 echo widget высотой 134 px
  показывает выбранный candidate из списка и ограничивает текст шестью строками
  вместе с query. Picker/Qt specs и resize routing: **8 examples, 0 failures**;
  семь целевых Ruby/spec файлов прошли RuboCop без offenses.
- Полный `bundle exec rake`: **198 examples, 0 failures**; полный RuboCop —
  **87 offenses** в 103 файлах. Provider coverage и line search/replace остаются
  закрыты отдельным следующим slice этапа 6.

## 2026-10-03 — этап 6: provider acceptance и обратимый поиск

- Сквозные application specs принимают command (`M-x`), buffer (`C-x b`),
  file path (`C-x C-f`), project/root file (`C-c p f`), line (`C-s`) и KillRing
  (`M-y`) candidates и проверяют действие после Enter. `FilePathProvider` specs
  отдельно покрывают Git ignore/exclusions и filesystem fallback.
- Buffer picker не выполняет preview при перемещении selection; cancel через
  `C-g` сохраняет исходный active buffer и point. Text query редактирование и
  cancel уже покрыты picker/search examples; backward search, goto-line,
  query-replace skip/replace-all/undo и cancel point restoration проверяются
  application specs.
- Полный `bundle exec rake`: **198 examples, 0 failures**. Полный RuboCop остаётся
  на **87 offenses** в 103 файлах; весь изменённый stage-6 model/provider/spec
  subset проходит целевой RuboCop.

## 2026-10-03 — этап 7: curses/Qt Unicode geometry и одиночный layout render

- `CursesTextGeometry` переводит core character columns в terminal cells,
  обрезает вывод только между grapheme clusters, считает combining marks,
  East Asian wide chars, skin-tone и ZWJ emoji. Runtime dependency
  `unicode-display_width` зафиксирована на 3.2.0. Minibuffer, modeline, picker,
  syntax boundaries и caret используют одну геометрию.
- Snapshot теперь отправляется сразу после startup, движения point и edits.
  Curses больше не переключается с snapshot renderer на прямой buffer redraw,
  поэтому syntax colors работают и в одном активном window. Qt сохраняет
  grapheme/UTF-16 caret mapping и HTML token spans.
- Настоящий PTY, Ruby **3.4.2**, curses gem **1.5.3**, `TERM=xterm-256color`,
  6×80: для `x = "🙂"; answer = 42 # note` захвачены SGR 32m/33m/37m для
  string/number/comment, caret после шести символов оказался в cell 8 (`CSI 8G`),
  процесс вышел с code 0 без traceback. Запуск не требовал split или xdotool.
- Тот же файл и keyboard flow с `TERM=vt100` завершились с code 0 без цветных
  token SGR — fallback отработал. В Qt Widgets **6.11.2** / gem `qt` **0.1.9** /
  offscreen настоящий `QTextEdit` сохранил number highlight после emoji.
- Tokenizer exception spec подтверждает fallback к пустым token rows. Unicode
  geometry, tokenizer, Qt highlighting/caret и snapshot specs: **19 examples,
  0 failures**.
- Полный `bundle exec rake`: **205 examples, 0 failures**. RuboCop — **87 offenses**
  в 105 файлах; новое geometry adapter и его specs проходят RuboCop.
- Настоящий curses PTY с `TERM=xterm-256color` вывел search match чёрным на
  жёлтом, а region — reverse-video. С `TERM=vt100` search match перешёл в
  standout, region сохранил reverse-video. Qt offscreen проверил жёлтый фон
  отдельного search range в реальном `QTextEdit`; mark продолжает отображаться
  как отдельное выделение.

## 2026-10-03 — точное положение Qt caret внутри grapheme

- `qt` 0.1.9 не предоставляет `QTextEdit#textCursor/#setTextCursor`. Qt pane
  кратко вставляет уникальный private-use marker на core character boundary в
  presentation HTML, находит его штатным `QTextEdit#find`, удаляет выделенный
  marker и до paint возвращает widget в read-only режим. Undo Qt отключён.
- Qt Widgets **6.11.2**, реальный offscreen `QTextEdit`: после caret между
  `e` и combining acute следующий Qt character movement скопировал только
  combining mark; caret после первого codepoint family emoji оставил справа
  остаток ZWJ sequence. Проверены также позиции после astral emoji, полного
  combining sequence и полного family emoji; marker отсутствует в widget text.
- На том же `QTextEdit` строка в 300 символов оставалась одной строкой и имела
  горизонтальный scrollbar; caret в конце перемещал scrollbar, resize сохранял
  прокрутку. Режим `QTextEdit::NoWrap` задан числовым enum, отсутствующим в gem.
- `spec/qt_editor_window_spec.rb`: **7 examples, 0 failures**. Mouse-to-core
  mapping, tab width, горизонтальная прокрутка core views и physical Super-key
  desktop smoke остаются открытыми.
- Полный RSpec: **208 examples, 0 failures**. RuboCop снизился с исходных
  **87 до 77 offenses**; целевые Qt caret/renderer/pane/spec файлы чисты.

## 2026-10-03 — ручная проверка Qt Super shortcut

- Пользователь физически проверил в живом Qt UI сочетание `M-s-k`: закрытие
  текущего buffer работает; затем подтвердил `s-,` и `s-.` для перехода между
  предыдущим и следующим buffer. Это подтверждает доставку и действие этих трёх
  сочетаний в его окружении; остальные Super shortcuts остаются непроверенными.

## 2026-10-03 — Qt wheel прокручивает core viewport

- Wheel-событие панели Qt передаёт количество строк, source и window id в
  `Event(:scroll_by)`; CommandHandler изменяет core viewport, сохраняя point.
  Qt scrollbar восстанавливается из snapshot `top_line`, включая отложенную
  раскладку документа. Page size берётся из реальных page/single шагов Qt.
- Qt Widgets 6.11.2 offscreen: настоящий `QTextEdit` с 100 строками после
  `top_line: 30` показывает scrollbar на 30 строках. Router spec проверяет
  wheel delta и source/window; Qt UI/shortcut и Application specs: **80 examples,
  0 failures**. Полный RSpec: **210 examples, 0 failures**. Изменённые файлы
  проходят RuboCop; общий gate всё ещё сообщает **63 offenses в 106 files**
  (тот же count, что до этого изменения).

## 2026-10-03 — Qt tab display width

- Qt HTML renderer expands source tabs to two-cell stops while retaining the
  original core text and character-column caret mapping. A real offscreen
  `QTextEdit` renders `界\t\tb` as `界    b`; moving right from the core position
  after the second tab and copying returns `b`.
- `qtimetrap` integration specs were reviewed for their approach: boot one real
  `QApplication`, exercise public widget actions, then process queued Qt events.
  Roded's real-widget specs use the same event-loop-aware pattern.
- Qt editor window specs: **9 examples, 0 failures**; tab renderer, expander and
  spec pass targeted RuboCop. The paired curses tab display and core horizontal
  scroll synchronization remain open.

## 2026-10-03 — Qt Menu key and native context menu

- Native `QTextEdit` defaults to `DefaultContextMenu`, which opened copy/select
  all actions instead of Roded's Menu bindings. Qt pane now sets the real widget
  property to `NoContextMenu`; Menu and Alt+Menu key payloads remain routed to
  project/buffer pickers.
- Offscreen Qt verifies the widget property, and shortcut routing specs exercise
  both Menu bindings. Targeted Qt UI/shortcut specs: **16 examples, 0 failures**.
  Full RSpec: **211 examples, 0 failures**. Physical Menu-key delivery will be
  confirmed with the remaining desktop checks. The overall RuboCop gate remains
  at **63 offenses in 107 files**; all files changed in this slice pass targeted
  RuboCop.

## 2026-10-03 — видимый Qt caret

- Реальный Qt `QTextEdit` сохраняет core caret и получает ширину системного
  caret 2 px. Presentation HTML подчёркивает текущий символ контрастной синей
  линией; это остаётся заметно даже пока native caret мигает или окно теряет
  focus. Текст, syntax colors, region и search overlay сохраняют свои стили.
- Offscreen widget проверяет cursorWidth, HTML underline marker, размер editor
  и положение modeline. Assertion на `has_focus` удалён: headless Qt иногда не
  назначает native focus даже при отрисованном layout/caret; результат зависел
  от порядка запуска spec. Изолированный Xvfb smoke ранее подтвердил получение
  настоящих `C-x C-c` и `C-n`.

## 2026-10-03 — Qt split ratio и Super arrows

- Qt synthetic Super+Right payload проходит через `QtInputRouter` и меняет
  core split ratio. Настоящий offscreen `QSplitter` отображает переданный ratio
  как 70/30 и сохраняет его при resize окна. Ранее тест выявил, что один
  `setStretchFactor` не применял новое отношение сразу; Qt adapter теперь
  задаёт стартовые размеры child widgets из core snapshot.
- `qtimetrap` specs тоже запускают настоящее Qt UI и проверяют observable widget
  state после обработки событий; здесь проверены реальные размеры дочерних
  widgets, а не только структура splitter. Physical `s-Left/s-Right` остаются
  в очереди пользовательских desktop checks. Полный RSpec: **214 examples,
  0 failures**. RuboCop снизился с **63 до 62 offenses в 107 files**; изменённые
  Qt files проходят targeted lint.

## 2026-10-03 — Qt initial render и frozen strings

- Реальный запуск через `bin/roded --frontend qt README.md` включал
  `frozen_string_literal`; `QtTabExpander` добавлял символы в замороженную
  строку. Ошибка возникала в отложенном render, поэтому окно оставалось пустым,
  редактор не получал focus и shortcuts не доходили до core. Строка результата
  теперь создаётся изменяемой. Первый layout рендерится до показа окна, чтобы
  первый видимый кадр уже содержал буфер и активный editor.
- Qt editor/shortcut/close specs под `RUBYOPT=--enable=frozen_string_literal`:
  **20 examples, 0 failures**; RuboCop затронутых файлов: **0 offenses**.
  Запуск в изолированном Xvfb с настоящими Qt Widgets показал содержимое README
  в первом кадре; физическая последовательность `C-x C-c` закрыла приложение.

## 2026-10-03 — Qt navigation and wheel input

- End-to-end Qt input integration specs send `C-n`/`C-p` payloads through the
  Qt router and application event loop, then assert the active window point.
  Wheel input advances core `top_line` and the real `QTextEdit` scrollbar to
  the matching position. Specs run with `frozen_string_literal`: **2 examples,
  0 failures**.
- Native X11 key and wheel events were also sent to the real Qt window in an
  isolated Xvfb display: two `C-n` events moved point to row 2; one wheel notch
  moved `top_line` to 3 and the scrollbar to 60. No user desktop input was used.
- После этого полного suite: **220 examples, 0 failures**; Qt editor/input/
  shortcut subset: **21 examples, 0 failures**. `bundle exec rake` пока падает
  только на оставшихся **57 RuboCop offenses** в `buffer.rb`, curses frontend,
  `window.rb` и одном spec.

### Fractional wheel regression

- Spec прокидывает два реальных Qt wheel payload-shaped события по `-60` через
  router, core event loop и widget scrollbar. Ранее отрицательный `divmod`
  интерпретировал первый half-notch как полный; накопление теперь делит с
  усечением к нулю и сохраняет signed remainder.
- `spec/qt_input_integration_spec.rb`: **3 examples, 0 failures**; targeted
  RuboCop чистый; полный RSpec: **221 example, 0 failures**. Общий lint debt
  остаётся **55 offenses**.

## 2026-10-03 — curses cursor-only redraw

- When layout, buffer contents, viewport and region are unchanged, cursor
  movement now redraws only the previous/current text rows, updates the
  modeline, and restores the cursor position. Edits, scrolling, region changes,
  viewport changes and layout changes keep the complete redraw path.
- A curses screen double asserts that navigation writes both affected rows and
  the modeline without clearing the screen; the dedicated spec passes. This
  reduces terminal output from the full visible buffer to at most two rows for
  ordinary navigation.

## 2026-10-03 — curses tab stops

- Curses now expands tabs to two-cell stops consistently in display clipping,
  cursor columns, styled line segments, and horizontal-origin calculations.
  Starting a clipped segment after an earlier tab preserves the source line's
  tab alignment. This matches Qt's existing two-cell tab stops.
- Geometry tests cover tabs after narrow text, viewport origins and clipping at
  a nonzero visual column; a curses rendering spec confirms a row containing a
  tab is written as expanded spaces. Curses geometry/render specs: **8 examples,
  0 failures**.

## 2026-10-03 — core routing and lifecycle cleanup

- Split command routing into prefix detection, exact resolution and character
  insertion helpers; separated window position fields in editor snapshots and
  buffer-removal publication from close prompting. Behavior remains covered by
  command-router/application specs: **77 examples, 0 failures**.
- Full RuboCop debt decreased from **61 to 57 offenses**; the three touched core
  files pass targeted lint.


## 2026-10-03 — табличная маршрутизация core input events

- `CommandHandler` заменил большой ветвящийся `case` на декларативные event maps
  и небольшие операции. Буферные действия, navigation/render feedback, команды,
  prompts и minibuffer edits используют тот же набор явно перечисленных event
  типов; unknown events остаются no-op.
- Полный RSpec: **208 examples, 0 failures**. `command_handler.rb` и
  `command_handler_event_maps.rb` проходят RuboCop без замечаний. Полный
  RuboCop снизился с **77 до 63 offenses**; выпускной gate пока не зелёный.

## 2026-10-03 — безопасная среда для Qt specs

- `spec/spec_helper.rb` принудительно выбирает `QT_QPA_PLATFORM=offscreen` и
  per-process `XDG_CONFIG_HOME` внутри системного temp directory, игнорируя
  унаследованные desktop Qt/user config settings. Это предотвращает запуск Qt
  specs на основном `DISPLAY` и обращения тестовых приложений к `~/.config`.
  Live UI smoke checks запускаются отдельно под Xvfb.
- Clipboard bridge specs: **4 examples, 0 failures**; полный RSpec:
  **220 examples, 0 failures**. RuboCop debt сейчас **55 offenses**, поэтому
  общий rake gate ещё красный.

## 2026-10-03 — position transforms views

- Упростил перевод point/mark после multi-line edit: replacement-row mapping
  теперь отдельный helper, а window layout specs разделены по независимым
  сценариям.
- Window/layout specs: **6 examples, 0 failures**; targeted RuboCop чистый.
  Эти правки помогли сократить общий lint debt до **55 offenses**.

## 2026-10-03 — независимые frontend input streams

- Application integration теперь регистрирует два frontend, передаёт `C-x`
  одному источнику, незнакомый chord второму и `C-c` первому. Prefix state не
  смешивается; маршрутизированный quit останавливает core. Это дополняет
  router unit spec независимой обработкой prefixes, late-frontend sync и
  Unicode/обычными edits в двух views одного buffer.
- Пять соответствующих Application/CommandRouter/Window examples: **5 pass**.

## 2026-10-03 — Qt live UI под изолированным Xvfb

- `script/qt_live_smoke.sh` запускает настоящий `bin/roded --frontend qt` на
  отдельном Xvfb (`xcb`, 1280×800×24) и задаёт временный `XDG_CONFIG_HOME` и
  лог. Скрипт ждёт первоначальный snapshot, кликает редактор, вводит `X`,
  сохраняет через `C-x C-s`, затем посылает wheel, `M->`, split, Super arrows и
  проверяет штатный выход по `C-x C-c`.
- Проверено на Ruby **3.4.2**, gem `qt` **0.1.9**, Qt Widgets **6.11.2**.
  Сценарий завершился успешно; лог содержит `C-n`, ввод `X`, `C-x C-s`,
  `scroll_by amount: 3`, `M->`, `C-x 3`, `s-Right`, `s-Left`, `C-x` и `C-c`.
  Split создал два panes и очистил prefix hint; приложение завершилось без
  signal cleanup. Файл на диске содержит `Xline
  002`; снимок после save показывает новый текст, чистый modeline и сообщение
  `File ... saved.`. Wheel переместил видимую область к строкам 004–037
  (modeline `5:1`); `M->` показал строки 069–100, caret на последней строке и
  modeline `100:9`.
- Снимки: `/tmp/roded-qt-live-smoke.3HA431/after-edit-save.png`,
  `after-wheel.png`, `after-meta-end.png`, `after-split.png`,
  `after-super-right.png` и `after-super-resize.png`. Проверка не использовала
  основной DISPLAY;
  X11-события не подтверждают физические клавиши Super.
- `bundle exec rspec`: **228 examples, 0 failures**; RuboCop по изменённым
  Ruby-файлам: **0 offenses**; `bash -n script/qt_live_smoke.sh` и
  `git diff --check` прошли.
- Общий `bundle exec rake` доходит до полного suite, но gate пока завершается
  на **55 RuboCop offenses** в двух файлах (`buffer.rb` и curses frontend;
  всего RuboCop проверяет 115 файлов).
- Диалог `roded-validationrc` был вызван отдельным runtime probe, который не
  загружал `spec_helper`; этот probe запускался с домашним config path. Отныне
  private `XDG_CONFIG_HOME` обязателен также для всех standalone Qt probes.

## 2026-10-03 — Qt mouse selection и Emacs-like caret

- `QtMouseInputAdapter` использует `QTextEdit#cursor_for_position` и Qt
  `QPoint#set_x/set_y`, преобразует UTF-16 hit-test offset в core row/column и
  отправляет mouse press/drag/release через `Event(:mouse_selection)`. Core
  синхронизирует point/mark и снова публикует editor snapshot; region copy
  остаётся общей командой `M-w` и записывает данные через Qt clipboard API.
- Caret показан контрастным синим block над символом; текущая строка получает
  приглушённый фон, syntax/region overlays сохраняют собственные цвета.
- Offscreen specs проверяют UTF-16 mapping для astral/combining/tab/multiline,
  реальный QTextEdit hit-test, press/drag/release routing и core mouse region
  copy. Полный suite: **233 examples, 0 failures**; targeted RuboCop: **16 files,
  0 offenses**.
- `script/qt_live_smoke.sh` под Xvfb `/tmp/roded-qt-live-smoke.ORaMLS` доставил
  mouse press/drag/release в редактор; log содержит 10 `mouse_selection` events,
  включая mark `{row: 4, col: 1}` -> point `{row: 4, col: 8}`, затем `M-w` и
  `clipboard_write`. Тот же smoke прошёл edit/save, wheel, `M->`, split,
  `s-Right`/`s-Left` и quit. Screenshot
  `/tmp/roded-qt-live-smoke.ORaMLS/after-edit-save.png` показывает block caret и
  подсветку активной строки. Проверка изолирована Xvfb и не использовала
  пользовательский DISPLAY.
- Повторный Xvfb smoke `/tmp/roded-qt-live-smoke.JIJ3rk` также посылает Qt
  `Menu` и `Alt+Menu` через `xdotool`: оба native key events попали в editor,
  открыли соответствующие core project/buffer pickers и отменились `C-g`.
  Smoke проверяет эти события и picker renders; пользовательский DISPLAY не
  используется. Проверка физической клавиши Menu на desktop остаётся отдельной.
- Визуальная проверка показала, что фон активной строки на `QTextEdit` должен
  быть задан форматированием всего paragraph block: теперь приглушённый фон
  проходит по всей ширине редактора и виден также на строке с текстом.
  Скриншот `/tmp/roded-qt-live-smoke.1Bgiul/after-edit-save.png`; связанные
  Qt editor/mouse specs: **19 examples, 0 failures**; RuboCop для двух
  изменённых Ruby-файлов: **0 offenses**. Xvfb smoke также прошёл.

## 2026-10-03 — редактируемая строка завершающего newline и Qt Space

- Core теперь включает последнюю пустую строку в `Buffer#lines`, когда текст
  заканчивается на `\n`. Курсор может находиться там; ввод превращает её в
  обычную строку, `Backspace` на её начале снимает завершающий newline, а
  `newline` добавляет ещё одну пустую строку. Undo возвращает исходные байты.
- Qt key translator теперь передаёт обычный Space как вставляемый пробел; Ctrl+Space
  по-прежнему переводится в `C-SPC`. На EOL caret остаётся после текста и не
  подсвечивает последний введённый символ.
- Добавлены core/window, curses draw, Qt caret/mapping, key-router и Qt input
  integration specs. Полный `bundle exec rspec`: **251 examples, 0 failures**;
  targeted RuboCop по изменённым key/UI/spec файлам: **0 offenses**.
- Изолированный Qt Xvfb smoke `script/qt_final_newline_smoke.sh` открыл файл
  `alpha\n`, перешёл `M->` в пустую строку, ввёл `x` и Space, сохранил
  `alpha\nx ` и закрыл редактор. Smoke использовал private `XDG_CONFIG_HOME`,
  не подключался к пользовательскому DISPLAY. Screenshot
  `/tmp/roded-qt-final-newline.bc1OHT/final-newline-caret.png` показывает block
  caret на второй строке, modeline `2:1`.
- Полный `script/qt_live_smoke.sh` после передачи page geometry также прошёл под
  отдельным Xvfb: `/tmp/roded-qt-live-smoke.qqOet4`, 17 key, 1 wheel и 12
  mouse-selection events, включая Menu/Alt+Menu pickers, resize и выход. Smoke
  harness проверяет первый UI по его логу и no-argument scratch по отдельному.

## 2026-10-03 — Qt caret на пустом документе и геометрия UI

- Пустая строка теперь всегда создаёт Qt paragraph. В пустом `*scratch*` видны
  фон активной строки и block caret; Xvfb снимок
  `/tmp/roded-qt-live-smoke.NEBmYw/empty-scratch.png` подтверждает кадр.
- У pane/window layouts и editor/labels обнулены margins и spacing; stylesheet
  отключает padding у widgets. Modeline отделена тонкой верхней границей.
  Проверяются реальные Qt layout/widget margins, spacing, label margin и border
  selector; live снимок `/tmp/roded-qt-live-smoke.NEBmYw/after-edit-save.png`.
- Полный Xvfb `script/qt_live_smoke.sh`: 17 key, 1 wheel, 12 mouse-selection
  events, Menu/Alt+Menu, split/resize, save, empty scratch и shutdown прошли.
  No-click keyboard/save сценарий `script/qt_final_newline_smoke.sh` также прошёл;
  `/tmp/roded-qt-final-newline.tQjKiJ/end-of-line-caret.png` показывает текст `x`
  и видимый block caret в ячейке после него. Оба smoke используют отдельный
  Xvfb/private config и не подключаются к desktop DISPLAY.
- Полный `bundle exec rspec`: **259 examples, 0 failures**; targeted RuboCop по
  Qt layout/render/focus/input и specs: **10 files, 0 offenses**.

## 2026-10-03 — Qt page geometry передаётся из GUI-thread

- Page movement key events измеряют размер текстового viewport активной Qt
  pane до передачи в core. `Application#page_size` использует этот размер на
  время команды, поэтому core не читает Qt scrollbar из своего потока.
- Application regression проверяет page size в event payload и падает, если
  core обращается к frontend. Qt input integration сравнивает `C-v` с реальным
  page size pane. Полный suite: **253 examples, 0 failures**; RuboCop для
  затронутых Ruby/spec файлов: **0 offenses**.

## 2026-10-03 — Qt UI dispatcher coalesces render snapshots

- Очередь UI dispatcher теперь synchronized и заменяет накопившиеся editor,
  picker и minibuffer state updates их последним состоянием. Сообщения и
  clipboard writes остаются отдельными FIFO actions. GUI timer забирает
  текущий batch и выполняет его на UI thread.
- Specs проверяют latest-wins для panes/picker/minibuffer, сохранение сообщений
  и clipboard, и что 500 render posts занимают одну позицию. Полный suite:
  **256 examples, 0 failures**; RuboCop dispatcher/spec: **0 offenses**.
- `script/qt_live_smoke.sh` повторно прошёл под Xvfb после coalescing:
  `/tmp/roded-qt-live-smoke.u8EkFU` — key, wheel, mouse-selection, split,
  Menu/Alt+Menu, resize, save и shutdown сценарии завершились успешно.

## 2026-10-03 — curses rendering modules and live quit routing

- Разделены curses input, viewport, layout, overlays, commands, color setup,
  modeline, line styling and styled-segment drawing into focused modules.
  Shared immutable drawing contexts replace positional bundles of coordinates.
- Live PTY check exposed that the `quit` command handler received its payload
  although `wake_getch` accepted no arguments. The wake method now accepts that
  unused payload; `spec/curses_command_spec.rb` covers the route.
- `script/curses_live_smoke.rb` запускает настоящий `bin/roded` в private PTY с
  временными XDG paths, отправляет `C-n` и `C-x C-c`, проверяет `move_cursor`,
  quit и exit без runtime error. Результат: pass; лог
  `/tmp/roded-curses-smoke.20261003-2-1w9sjx/roded.log`. Пользовательский
  terminal/display не используется.
- После исправления: `bundle exec rake` — **260 examples, 0 failures**;
  RuboCop — **144 files, 0 offenses**.
- Последовательно, в изолированных Xvfb, прошли `script/qt_live_smoke.sh`
  (`/tmp/roded-qt-live-smoke.ONE3Rx`, включая no-argument empty scratch) и
  `script/qt_final_newline_smoke.sh`
  (`/tmp/roded-qt-final-newline.pJSPuN`). Empty scratch screenshot показывает
  активную строку во всю ширину и видимый block caret; final-newline smoke
  проверил ввод Space и сохранение. Оба запуска не использовали desktop DISPLAY.
- Первый параллельный запуск двух xdotool/Xvfb smoke дал нестабильные результаты
  ввода; последовательный запуск обоих сценариев прошёл. Запускать эти два
  desktop smoke последовательно.

## 2026-10-03 — Qt minibuffer height follows its visible rows

- `QtEchoArea` now uses a fixed vertical size policy and recalculates its fixed
  height from the Qt font line spacing and displayed line count. This keeps an
  empty minibuffer at one line and lets picker rows grow it without letting the
  echo widget consume half of a split window. The picker row budget is based on
  the parent window height, rather than the now-small echo widget height.
- Qt offscreen split geometry checks verify one-line empty echo, editor content
  taking over 90% of a 960x640 window, and a multi-line picker sizing the echo
  to the exact number of visible lines. Picker/editor-window specs: **27
  examples, 0 failures**. Full `bundle exec rake`: **261 examples, 0 failures**;
  RuboCop: **144 files, 0 offenses**.
- `script/qt_live_smoke.sh` passed in a private Xvfb with `QT_QPA_PLATFORM=xcb`
  and private `XDG_CONFIG_HOME`: 17 key events, wheel, mouse selection,
  Menu/Alt+Menu, split, Super resize and no-argument scratch startup all passed.
  The live split screenshot is `/tmp/roded-qt-live-smoke.kWKKeS/after-split.png`;
  it shows both editor panes filling the window above the one-line echo area.
  This run used Qt Widgets **6.11.2** and gem `qt` **0.2.0**; no desktop
  `DISPLAY` was used.

## 2026-10-03 — editor message contracts and command registry

- Frontends and runtime publish `InputEvent`; keymap resolution returns a
  separate `EditorCommand`; UI publications have the `UIUpdate` type. The old
  `Event` and `Command` constants remain aliases for existing adapters. The
  application checks the input boundary, and the command handler rejects raw
  input events. Routed commands retain their originating `source_id` and
  `view_id` through the application path.
- The shared command registry is exercised through key bindings, `M-x`, and
  the in-process Ruby editor API. Specs cover runtime registration/execution,
  command catalog output, typed routing, and source/view preservation.
- Full `bundle exec rake`: **266 examples, 0 failures**; RuboCop: **145 files,
  0 offenses**. `script/curses_live_smoke.rb` passed in a private PTY with
  `C-n` and `C-x C-c`. `script/qt_live_smoke.sh` passed in private Xvfb with
  Qt Widgets **6.11.2** / gem `qt` **0.2.0**: 17 key events, wheel, mouse
  selection, Menu/Alt+Menu, split, Super resize, and scratch startup passed.
  Screenshots/log: `/tmp/roded-qt-live-smoke.HzEMxJ`; no desktop `DISPLAY` was
  used.

## 2026-10-03 — UI state uses one frontend update channel

- Added `Application#publish_ui_update` as the single core-to-frontend update
  channel. Editor snapshots, minibuffer/picker state, messages, focus, clipboard
  and shutdown all travel as `UIUpdate` values. The former `broadcast_command`
  API remains as an alias for compatibility; internal application operations
  use the update API directly.
- Curses and Qt no longer subscribe to `Buffer` observers for rendering, and
  application operations no longer call frontend `render` or
  `display_message` methods directly. Curses input uses the same render snapshot
  publication; Qt posts snapshots through its GUI-thread dispatcher.
- Qt integration verifies normal key navigation works without a Buffer UI
  observer. Offscreen application/frontend specs cover file-open, late attach,
  edit snapshots, focus, messages and clipboard. Full `bundle exec rake`:
  **266 examples, 0 failures**; RuboCop: **145 files, 0 offenses**.
- Real `script/curses_live_smoke.rb` passed in private PTY (`C-n`, edit-loop
  routing, `C-x C-c`): `/tmp/roded-curses-smoke.20261003-2-xanvss`.
  Real `script/qt_live_smoke.sh` passed under private Xvfb / Qt Widgets **6.11.2**
  / gem `qt` **0.2.0**: key editing/save, scrolling, selection, Menu/Alt+Menu,
  split, Super resizing, empty scratch and quit; screenshots/log are in
  `/tmp/roded-qt-live-smoke.wNTMqA`. Neither smoke used desktop `DISPLAY`.

## 2026-10-03 — immutable UI updates and core event-loop ownership

- `UIUpdate` deep-copies and freezes nested hashes, arrays and strings at
  publication. A regression spec mutates the original payload after creating
  an update and verifies that the delivered snapshot remains unchanged and
  deeply frozen. Unsupported mutable payload values fail immediately.
- A core-queue spec registers and executes a command through `RubyEditorAPI`
  from outside the event loop and verifies that the command action runs on the
  event-loop thread. Frontend readers and the REPL worker enqueue input/API
  events; the application loop handles mutations serially.
- Targeted message/Qt input/clipboard specs: **18 examples, 0 failures**;
  message/API specs: **12 examples, 0 failures**. `bundle exec rake`:
  **269 examples, 0 failures**, RuboCop **145 files, 0 offenses**.
- `script/curses_live_smoke.rb` passed in a private PTY (`C-n`, `C-x C-c`):
  `/tmp/roded-curses-smoke.20261003-2-f0gf2k`. `script/qt_live_smoke.sh`
  passed in private Xvfb / private `XDG_CONFIG_HOME` with Qt Widgets **6.11.2**
  and gem `qt` **0.2.0**: 17 key events, wheel, mouse selection, Menu/Alt+Menu,
  split, Super resize, no-argument scratch startup and keyboard quit; screenshots
  and log are in `/tmp/roded-qt-live-smoke.xCZAwA`. Neither check used the
  user's desktop `DISPLAY`.

## 2026-10-03 — EditorSession owns document collection and view tree

- Added `EditorSession` as the sole owner of the application buffer collection,
  active view and logical `WindowLayout`. Active buffer is derived from the
  active window; the old duplicate `@buffers`, `@windows`, `@current_buffer`,
  `@current_window` and `@window_layout` fields were removed from `Application`.
  The Qt adapter continues to own physical widget/splitter geometry.
- Regression coverage verifies session/application buffer and view access,
  absence of duplicated application state, active-buffer switching, and keeps
  application scenarios for startup, file open/close, split and multiple views.
- `bundle exec rake`: **270 examples, 0 failures**, RuboCop **147 files, 0
  offenses**. Curses private PTY smoke passed (`C-n`, `C-x C-c`), output
  `/tmp/roded-curses-smoke.20261003-2-savjwe`. Qt private-Xvfb smoke passed
  under Qt Widgets **6.11.2** / gem `qt` **0.2.0**: 17 key events, wheel, mouse
  selection, Menu/Alt+Menu, split, Super resize, scratch startup and quit;
  screenshots/log: `/tmp/roded-qt-live-smoke.kAgSKX`. The user's desktop was
  not used.
- `CommandHandler` still receives the application facade, and `Buffer` still
  retains a compatibility cursor alongside each `Window` point. Those are
  separate remaining Stage 2 migrations and are not marked complete.

## 2026-10-03 — undo/redo input and Qt shutdown thread

- Qt sends Ctrl+/ as U+001F and curses receives byte `0x1f`; both frontends now
  normalize that control character to the existing `C-_` undo binding. Typing
  contiguous characters forms one undo group, broken by navigation or another
  command. Core, Qt payload, and curses decoder specs cover the route; a live
  Qt widget sequence verifies edit → Ctrl+/ undo → `C-c r d` redo.
- The undo/redo regression is also exercised in both actual frontends. The
  curses private-PTY smoke sends typed characters, Ctrl+_ undo, `C-c r d` redo,
  and checks saved file contents. Log: `/tmp/roded-curses-smoke.20261003-277107-n78cfr`.
  The Qt smoke runs in private Xvfb with private `XDG_CONFIG_HOME`, sends the
  corresponding keyboard sequence, waits for the rendered snapshot, and checks
  the visible widget/modeline and saved contents. Log/screenshots:
  `/tmp/roded-qt-live-smoke.Z7yx4k`. Neither test
  uses the desktop `DISPLAY`.
- A real `QTimer` dispatcher spec records that worker-posted messages and quit
  actions run on the GUI thread. Another Qt integration spec raises an
  exception in the core loop and verifies the visible window closes without a
  hang. Snapshot feedback remains covered by a real editor widget spec.
- `bundle exec rake`: **277 examples, 0 failures**; RuboCop: **148 files, 0
  offenses**. The live Qt smoke covered 25 key events, wheel, 12 mouse
  selections, Menu picker, Ctrl+/ undo and C-c r d redo; Qt Widgets **6.11.2**,
  gem `qt` **0.2.0**. The curses smoke passed in a private PTY.

## 2026-10-03 — redo coverage for composite edits

- Added redo assertions for final-newline insertion/removal, CRLF region cuts,
  paste events, region kill/yank/yank-pop, query replace, current/region indent,
  tabify/untabify, and `binding.irb` insertion. Existing checks cover insert,
  delete, backspace, newline split/join, kill-line, grouped typing/paste,
  saved-state restoration, redo invalidation, and Ruby editor API edits.
- Targeted Buffer/Application/indent/text-command specs: **118 examples, 0
  failures**. Full suite and live frontend evidence are recorded with the
  preceding undo-routing entry.

## 2026-10-03 — readonly edit entrypoints

- A readonly audit found that `replace-all` could loop forever because rejected
  edits left the current match in place. `query-replace` now exits with a clear
  message before either single or replace-all edits run.
- Application integration covers readonly mark/region, cut, copy, yank,
  yank-pop, kill-line, paste, query-replace, undo and redo. Copy and navigation
  remain available; rejected edits preserve document text and KillRing. Existing
  Buffer, text-command, and Ruby editor API specs cover their readonly paths.
- `bundle exec rspec spec/application_spec.rb`: **74 examples, 0 failures**.
  Full `bundle exec rake`: **279 examples, 0 failures**; RuboCop: **148 files,
  0 offenses**.

## 2026-10-03 — movement and bracketed paste in real curses

- Application routing specs verify M-f/M-b word movement and M-</M-> document
  boundaries. The private curses PTY exercises M-</M->, C-n, typing, and sends
  an actual bracketed multiline paste (`A`, newline, `B`); it saves, undoes with
  Ctrl+_, redoes with `C-c r d`, and compares each complete file state. Output:
  `/tmp/roded-curses-smoke.20261003-277107-n78cfr`.
- Qt's real QWidget checks that a 300-character unwrapped line scrolls to the
  caret; curses geometry specs cover horizontal origins, tabs, wide and
  combining graphemes. The isolated Qt Xvfb smoke also exercises M->.
- Headless Application integration already covers open/edit/save/close/quit,
  file errors/conflicts, shutdown exceptions, and cancel flows.
- `bundle exec rake`: **280 examples, 0 failures**; RuboCop: **148 files, 0
  offenses**.

## 2026-10-04 — viewport follows point and curses horizontal redraw

- Core now synchronizes `Window#top_line` when routed cursor movement, document
  jumps, mouse selection, or terminal resize moves the point outside the active
  text area. The page geometry belongs to the input source and active view;
  captured event geometry is used without calling the frontend. A regression
  starts with a four-row viewport, moves `C-n` past its edge, jumps to `M->`,
  then scrolls back and checks that point and origin remain aligned.
- Custom `M-p`/`M-n` line scroll and `M-P`/`M-N` page scroll retain the documented
  core policy: the viewport and point move together, preserving screen row up
  to document bounds. Application coverage asserts each movement and boundary.
- Curses incremental redraw now falls back to a full layout render when
  horizontal scrolling changes the origin; otherwise rows that were not under
  the caret could keep text from the previous origin. A rendering regression
  checks both rows use the new origin. Qt real-widget coverage continues to
  verify caret visibility, scrolling, and scrollbar synchronization.
- `bundle exec rake`: **282 examples, 0 failures**; RuboCop: **148 files, 0
  offenses**. `script/curses_live_smoke.rb` passed in private PTY with M-</M->,
  C-n, typing, bracketed paste, undo/redo, save and quit:
  `/tmp/roded-curses-smoke.20261004-285671-i61dtu`.
- `script/qt_live_smoke.sh` passed under private Xvfb and private
  `XDG_CONFIG_HOME`: 25 keys, wheel, 12 mouse selections, Menu pickers,
  Ctrl+/ undo, `C-c r d` redo, scratch startup and keyboard quit. Qt Widgets
  **6.11.2**, gem `qt` **0.2.0**; screenshots/log:
  `/tmp/roded-qt-live-smoke.3g2v5k`. Neither live check used desktop `DISPLAY`.

## 2026-10-04 — Qt native close and modified-buffer decisions

- A real `QWidget.close()` now has integration coverage through the Qt event
  router and application core. For a dirty file, the echo area shows the
  save/discard/cancel prompt; save writes the exact edited content, discard
  exits without changing the file, and cancel preserves both the dirty buffer
  and visible window.
- `script/qt_live_smoke.sh` also runs each decision against the visible editor
  under private Xvfb. Save and discard exit with their expected file contents;
  cancel leaves the process alive, after which Ctrl+/ undoes and C-x C-c exits.
  Log and screenshots: `/tmp/roded-qt-live-smoke.UXRx3x`. This does not use the
  user's desktop display or window manager.
- Targeted `bundle exec rspec spec/qt_close_prompt_integration_spec.rb`:
  **1 example, 0 failures**; targeted RuboCop: **1 file, 0 offenses**. Full
  `bundle exec rake`: **283 examples, 0 failures**; RuboCop: **148 files, 0
  offenses**. `bash -n script/qt_live_smoke.sh` and `git diff --check` pass.

## 2026-10-04 — curses function keys, Unicode bytes and EOF

- Curses decodes xterm navigation, paging and function sequences, including
  F7 (`ESC [ 18 ~`) for Save. UTF-8 characters are reassembled across the
  decoder's one-byte reads. Pipe EOF and PTY `EIO` now propagate as frontend EOF
  so the application runtime can run terminal cleanup instead of spinning on
  noop input.
- `spec/curses_input_decoder_spec.rb` covers control bytes, NUL, Unicode,
  xterm Home/End/PageUp/PageDown/Delete/F7/F1/F12, fragmented bracketed paste,
  and EOF. `script/curses_live_smoke.rb` sends F7 to the actual curses process;
  the file remains byte-for-byte unchanged and the log records the `F7` token.
  The same PTY verifies both terminal `0x1f` (`C-_`) and `C-x u` undo by
  saving the buffer after each transition; typing and bracketed-paste redo
  restore the exact edited bytes. It also cancels a dirty quit and confirms
  edits survive before a final clean quit. `spec/application_spec.rb` covers
  choosing between same-basename buffers using their full paths.
- The private PTY smoke passed for `M-</M->`, `C-n`, typing, bracketed paste,
  `C-_`, `C-x u`, `C-c r d`, F7 save, dirty-quit cancel/undo and clean quit;
  log: `/tmp/roded-curses-smoke.20261004-319015-farc30`.
- `bundle exec rake`: **288 examples, 0 failures**; RuboCop: **148 files, 0
  offenses**.

## 2026-10-04 — curses undo and redo through a terminal emulator

- The private PTY smoke above sends terminal byte `0x1f` directly. To verify
  the keyboard mapping too, `script/curses_xvfb_keyboard_smoke.sh` starts
  Alacritty **0.17.0** and the real curses app under Xvfb, with private
  `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and `XDG_RUNTIME_DIR`. Curses requests
  Kitty CSI-u reporting, and `xdotool` sends Ctrl+/ and Ctrl+Shift+/ through
  Alacritty. The app receives `C-/` and `C-?`; saving after undo and redo
  matches the expected complete file bytes. The process exits cleanly.
- Runtime: Ruby **3.4.2**, curses gem **1.5.3**, `TERM=xterm-256color`, Alacritty
  X11 on isolated Xvfb (1280×800×24). Command and result:
  `script/curses_xvfb_keyboard_smoke.sh` — passed; log:
  `/tmp/roded-curses-xvfb.2VKzx3/roded.log`. It also verifies Ctrl+N movement,
  typing and save. No desktop `DISPLAY` was used. CSI-u decoding and the
  `C-?` redo binding are covered by RSpec; `C-c r d` remains the fallback for
  terminals that do not support the reporting protocol.
- `script/qt_live_smoke.sh` also passed under private Xvfb with real Qt Widgets
  6.11.2. It sends Ctrl+Shift+/ through xdotool, verifies the live app receives
  `C-?`, and confirms the saved buffer is redone. It then checks the
  `C-c r d` fallback after another undo. Screenshots and log:
  `/tmp/roded-qt-live-smoke.IyLiot`; no desktop `DISPLAY` was used.
- `script/curses_live_smoke.rb` passed again after the decoder change in a
  private PTY; it covered legacy Ctrl+_, C-x u undo and C-c r d redo:
  `/tmp/roded-curses-smoke.20261004-341835-ygudgn`.
- `bundle exec rake`: **290 examples, 0 failures**; RuboCop: **148 files, 0
  offenses**. `git diff --check` and `bash -n` for both live smoke scripts pass.

## 2026-10-04 — remove legacy console status bar

- `Roded::Window` is the logical editor view with independent point/mark and
  viewport state. The unused legacy `Roded::StatusBar` wrote directly to stdout
  and is no longer loaded or packaged; curses and Qt each render their own
  modeline. Updated `AGENTS.md` to describe the current core modules and avoid
  reintroducing the stdout presentation class.
- `rg -n 'StatusBar' lib spec` returns no references. `bundle exec rake`:
  **282 examples, 0 failures**; RuboCop: **147 files, 0 offenses**.

## 2026-10-04 — narrow CommandHandler context

- `CommandHandler` no longer stores or calls `Application`. Its command-facing
  operations are exposed through `ApplicationCommandContext`, which is the
  Application adapter; the routing layer can be exercised with a context test
  double. Existing key, M-x, minibuffer and UI update flows remain end-to-end.
- `spec/command_handler_spec.rb` verifies buffer and minibuffer routing against
  the context contract. `bundle exec rake`: **292 examples, 0 failures**;
  RuboCop: **150 files, 0 offenses**.
- Sequential isolated UI checks passed: Alacritty+curses under private Xvfb
  verifies Ctrl+N, edit/save, undo, Ctrl+? redo and quit at
  `/tmp/roded-curses-xvfb.T8ssDt/roded.log`; Qt Widgets **6.11.2** under
  private Xvfb checks editing, both redo bindings, Menu, wheel, mouse selection,
  Super resize, close decisions and scratch startup at
  `/tmp/roded-qt-live-smoke.B9R3oF`. They were run separately, without the
  desktop `DISPLAY`.

## 2026-10-04 — move cursor ownership into Window

- `Buffer` no longer stores, exposes or moves a cursor. Character/line edits
  require an explicit `at:` position; edit history stores only document
  fragments and newline metadata. `Window` owns point, mark, movement and
  per-buffer position memory, and each view transforms its own positions when
  shared text changes or undo/redo replays.
- Added coverage for Buffer's cursor-free API, edit and undo position mapping,
  independent views, and remembered point/mark mapping while a view temporarily
  displays another buffer. Reloading a buffer resets attached and remembered
  positions. `bundle exec rake`: **293 examples, 0 failures**; RuboCop: **151
  files, 0 offenses**.
- Real curses PTY smoke passed, including navigation, typing, paste, undo/redo,
  save and quit: `/tmp/roded-curses-smoke.20261004-383541-plefod`. Actual
  Ctrl+N, Ctrl+/, Ctrl+Shift+/ keys passed through Alacritty in private Xvfb:
  `/tmp/roded-curses-xvfb.GNG3rP/roded.log`.
- `script/qt_live_smoke.sh` passed with Qt Widgets **6.11.2** under private
  Xvfb: editing, `C-/` undo, `C-?` redo, `C-c r d`, Menu, Super shortcuts,
  mouse selection/scrolling and close decisions all passed. Log/screenshots:
  `/tmp/roded-qt-live-smoke.NlgCuM`. No check used the user's desktop display.
