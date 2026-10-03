# Проверки первой рабочей версии Roded

Этот журнал содержит воспроизводимые результаты текущей ветки. Исторический
отчёт ревизии остаётся в `architecture-review-2026-10-03.md`.

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
  остаётся открытой. XTest/xdotool — синтетический ввод и не вызывает sound API.
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
