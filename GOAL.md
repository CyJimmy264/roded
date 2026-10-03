# Goal: первая рабочая версия Roded

## Задание агенту

Доведи Roded в ветке `1-architecture` до рабочего редактора с curses и Qt frontend,
которым можно пользоваться для повседневного редактирования нескольких файлов.
Реализуй все обязательные возможности ниже, следуя `PLAN.org`, и заверши работу
только после выполнения критериев готовности. Основные законченные этапы
коммить отдельными осмысленными коммитами. Одной подготовки архитектуры, тестов
или демонстрации отдельных компонентов недостаточно.

Перед началом прочитай `AGENTS.md`, этот файл, `PLAN.org`,
`docs/architecture-review-2026-10-03.md` и `docs/keybindings.md`.
Для Qt прочитай `docs/qt-frontend.md` и указанные там локальные источники.
Продолжай существующую реализацию маленькими шагами. Выбирай детали реализации
самостоятельно внутри этого задания. При обнаружении новых проблем исправляй
их, если они мешают обязательным сценариям. Не останавливайся после каждого
коммита за подтверждением следующего уже описанного этапа.

Этот файл определяет продукт и критерии готовности; `PLAN.org` — порядок работы
и текущие статусы. Проверенные результаты фиксируй в
`docs/working-editor-validation.md` по мере реализации. Не отмечай возможность
готовой только по наличию класса, команды в реестре или сообщения для frontend.

## Границы версии

- Ruby 3.4+, Linux, curses TUI в UTF-8 терминале и Qt GUI на пользовательском
  gem `qt` (исходники `/home/mveynberg/Code/Ruby/qt`). Проверенные terminal/TERM,
  Qt/gem versions и display backend должны быть записаны в документации.
- Несколько открытых документов без искусственного лимита числа buffers;
  разделение экрана по горизонтали и вертикали, переключение между окнами.
- Emacs-подобное немодальное редактирование и тёмное оформление по мотивам
  Spacemacs. Полная совместимость с Emacs/Evil не требуется.
- Подсветка минимум Ruby, JSON, YAML и Markdown; встроенный Ruby REPL;
  общий интерактивный выбор файлов, буферов, команд, строк и kill ring.
- Архитектура core остаётся независимой от curses и Qt. Обязательные действия
  доступны в обоих frontend через общий core. Несколько независимых источников
  ввода проверяются с doubles; одновременный curses+Qt в одном процессе и
  несколько desktop frames пока не обязательны.

Вне обязательного объёма: web/прочие GUI frontend, collaboration, LSP, отладчик,
Magit, project perspectives, Org/journal, tree sidebar, Vim/Evil modes,
макросы, структурное редактирование, folding, внешний formatter и полноценный
plugin framework. Установленные в личных Emacs-конфигах пакеты не расширяют
этот список требований. Перенос всех Emacs-конфигов не нужен.

## Обязательное поведение

### 1. Запуск, файлы и сохранение

`bundle exec bin/roded [file ...]` запускает curses редактор, создаёт хотя бы одно
окно и открывает переданные пути. Без аргументов доступен writable `*scratch*`
и понятная подсказка по основным командам. Read-only welcome может быть
дополнительным буфером, но не должен мешать начать редактирование.

`C-x C-f` предлагает путь с completion и открывает файл в активном окне.
Несуществующий путь создаёт новый несохранённый file buffer; родительский
каталог не создаётся без явного действия пользователя. Повторное открытие
того же существующего файла активирует его buffer и не стирает правки.
Определи нормализацию путей, включая относительные пути, `~` и symlinks;
разные написания одного существующего пути не создают случайные дубликаты.

`C-x C-s` / F7 сохраняют текущий buffer; buffer без filename запрашивает путь.
`C-x C-w` выполняет save as. Ввод имени отменяется через `C-g`. При попытке
перезаписать другой существующий файл требуется понятное подтверждение в UI.
Сохранение обычного файла выполняется безопасной заменой через временный файл
в его каталоге: не обнуляет исходник до успешной записи, сохраняет необходимые
permissions и не уничтожает symlink. Ошибка оставляет edits и modified state.

Open → save без edits сохраняет текст: пустой файл, наличие/отсутствие final
newline, LF/CRLF, UTF-8 и кириллицу. Поддерживаемые окончания строк и BOM
обрабатываются явно; неподдерживаемые binary/encoding данные дают сообщение,
а не молчаливую повреждённую перезапись. Не применять trim/chomp, уничтожающие
существенную информацию. Не нормализовать mixed line endings молча: сохранить
их или явно отказаться от редактирования такого файла с объяснением.

Modeline показывает modified state. Save сбрасывает его только после успеха;
undo до сохранённого состояния также делает buffer unmodified.
Закрытие изменённого buffer и выход предлагают save/discard/cancel. Отмена
возвращает исходное состояние окон и правок. Обнаруженное изменение файла на
диске после открытия/сохранения требует выбора reload/overwrite/cancel;
не терять edits при отмене или ошибке reload.

### 2. Документы, окна и навигация

Buffer — документ; editor window/view — отображение документа со своими point,
mark и памятью позиций при переключении buffers. Два окна могут показывать
один Buffer: текст общий, позиции курсоров независимы. Edits и undo корректно
адаптируют позиции остальных views; ни один курсор не выходит за границы.
Buffer переключается только в активном окне и сохраняет свои edits и историю.

`C-x b` выбирает buffer, `C-x <left>/<right>` переключают предыдущий/следующий,
`C-x k` закрывает buffer с проверкой modified state. Отображения закрытого
buffer заменяются согласованно; всегда остаётся доступное окно и writable
buffer. Имена одноимённых файлов из разных каталогов различимы в picker/modeline.

`C-x 2` разделяет окно сверху/снизу, `C-x 3` — слева/справа, `C-x o`
переключает активное окно, `C-x 0` закрывает текущее окно, `C-x 1` оставляет
только текущее. Закрытие окна не закрывает документ. Попытка деления слишком
маленького окна показывает сообщение; закрытие последнего окна не рушит UI.
После изменения размера терминала layout корректно перерасчитывается, включая
очень маленький экран. Активное окно и его modeline визуально различимы.

Page up/down используют высоту текстовой области активного окна. Viewport
учитывает modeline/minibuffer/picker и не скрывает реальную позицию point.
Длинные строки поддерживаются горизонтальным scrolling; truncation cursor
до края экрана не заменяет scrolling. Переключение buffer/window не оставляет
на экране состояние предыдущего документа.

### 3. Редактирование, undo, region и поиск

Работают вставка, Backspace/Delete, Enter, стрелки, Emacs перемещения по
символам/словам/строкам, начало/конец строки и документа, page movement.
Tabs отображаются с определённым tab width. Tab/indent-region дают минимальное
предсказуемое отступление, для Ruby — два пробела; полноценный formatter не нужен.
UTF-8 ввод и terminal paste не превращают управляющие символы вставляемого
текста в editor commands. Bracketed paste сохраняет многострочный текст и
образует одну undo-операцию. Cursor/selection и scrolling учитывают ширину
terminal cells, минимум ASCII, кириллицу, tabs и wide Unicode; combining
characters не должны повреждаться или ломать отрисовку.

Есть undo/redo с независимой историей каждого Buffer. Вставка, удаление,
newline, region edits, kill/yank, indent, replace и поддерживаемые Ruby API
edits обратимы. Навигация и redraw не создают edits; после undo новая правка
инвалидирует redo. Группировка набора текста определена и проверена, undo не
вынуждает отменять длинную paste посимвольно.

`C-SPC` ставит mark, region виден; `C-w` вырезает, `M-w` копирует, `C-y`
вставляет. `C-k` удаляет до конца строки, на EOL — newline, и помещает реально
удалённый текст в KillRing. Последовательные kill-команды предсказуемо объединяются.
`M-y` открывает выбор из KillRing по образцу consult-yank-pop: после yank
заменяет предыдущую вставку, иначе вставляет выбранный текст. Read-only buffers
поддерживают навигацию/копирование, но защищены от всех путей изменения текста.

`C-s` открывает поиск по строкам текущего Buffer, как в vanilla config:
query фильтрует строки, выбор перемещает point, `C-g` отменяет выбор и preview.
Есть команды поиска вперёд/назад, перехода к номеру строки и замены текста с
подтверждением (`query-replace`, включая cancel/skip/replace/all).
Search, replace и selection работают с кириллицей и через границы viewport.

### 4. Emacs-подобный UI и конфигурация

Основная область — окна с текстом; у каждого modeline с buffer name, modified /
read-only признаками, mode и row/column. Внизу общая echo/minibuffer area для
prompts, ошибок, подсказок и picker query. Тёмная палитра, понятные syntax
colors, region и search matches; UI остаётся читаемым без color support.
Line numbers по умолчанию выключены, как в vanilla config.

`C-g` отменяет prefixes, prompts, picker/search и активное выделение, не
закрывая редактор. Неизвестная key sequence показывает сообщение и не
вставляет её остаток неожиданно. Pending prefix виден в echo area.
Keymap допускает произвольные последовательности, например `C-c r r`,
префиксы выводятся из bindings; user bindings имеют документированный приоритет.
В Qt поддерживаются Super и комбинации Ctrl/Alt/Super/Shift; одно действие
нельзя выполнить дважды через QShortcut и raw event. Emacs Meta соответствует
Alt, Emacs Super — Qt MetaModifier на целевом Linux, это разные модификаторы.

`M-x` выбирает и выполняет зарегистрированную команду. Клавиатура, `M-x` и
Ruby API используют один контракт команд. `C-h b` / `M-x describe-bindings`
открывают справку по реальным bindings и командам. User keymap остаётся
настраиваемым, конфигурационные ошибки показываются понятным сообщением.
Полная таблица обязательных и отложенных bindings — в `docs/keybindings.md`.

### 5. Подсветка синтаксиса

По filename/mode определяются минимум Ruby, JSON, YAML и Markdown; остальные
файлы редактируются как plain text. Mode можно сменить через команду.
Подсветка Ruby различает comments, strings, keywords, numbers и symbols;
учитывает multiline constructs и изменения текста, включая незавершённый код.
Для остальных обязательных modes нужен полезный минимальный набор категорий.

Highlighting не меняет текст, modified state, point или undo. Ошибка tokenizer
не ломает editor loop; допустим fallback к plain text с диагностикой.
Token spans — данные независимого сервиса/mode, frontend только отображает их.
Не встраивать полноценный LSP/tree-sitter framework ради этого этапа.

### 6. Встроенный Ruby REPL

`M-x ruby-repl` / `C-c r r` открывают отдельный `*ruby*` buffer в окне.
Он работает **в процессе Roded** с persistent binding, history, multiline
input, результатами выражений, stdout/stderr и понятными исключениями.
IRB можно использовать, если корректно интегрируется с обоими UI; самостоятельный
REPL на Ruby stdlib допустим. Запуск внешнего процесса IRB без доступа к живым
объектам редактора не удовлетворяет заданию.

Из REPL доступны реальные state/buffers/windows для инспекции и поддерживаемый
Ruby API для изменения текста, открытия/сохранения файла, переключения view,
выполнения команды и регистрации новой команды/binding. README содержит
работающие примеры. Изменение buffer через этот API отображается во всех его
окнах, учитывает readonly, modified state и undo.

Evaluation и domain mutations согласованы с единственным владельцем состояния;
параллельный доступ к live state не должен создавать гонки. Stdout/stderr и
exceptions остаются внутри REPL/messages, не портят экран. Ошибочное выражение,
`Interrupt` и обычный `exit` не завершают editor process; `exit` закрывает REPL
interaction. Предусмотри прерывание простого длительного Ruby-вычисления и
сохранение работоспособности UI, проверь его отдельным сценарием. Документируй
ограничения trusted in-process Ruby, не обещая изоляции произвольного кода.

### 7. Минимальный аналог Helm / Consult

Один переиспользуемый picker: query, список кандидатов, текущий выбор,
live filtering, `C-n/C-p` / стрелки, Enter, `C-g`, корректный scrolling и
resize. Несколько слов query совпадают независимо от порядка, без учёта
регистра; порядок результатов стабилен. Полная fuzzy scoring совместимость
с Helm не нужна. Пустой список не приводит к исключению.

Обязательные providers: команды (`M-x`), открытые buffers (`C-x b`), пути
(`C-x C-f`), строки (`C-s`), KillRing (`M-y`), файлы текущего project/root
(`C-c p f`). File-path provider позволяет создавать новый путь, project-file
provider выбирает существующие файлы рекурсивно. В Git root учитывай ignore
rules; `.git` и сгенерированные cache directories не должны забивать список.
Вне Git используй рабочий root с документированными exclusions.

Provider отделён от curses и query UI. Если используется preview, cancel
восстанавливает прежний buffer/window/point; простой просмотр кандидатов не
открывает необратимо десятки buffers. Набор пустых/Unicode candidates, длинные
пути и маленький терминал покрыты проверками.

### 8. Qt frontend и Super

`bundle exec bin/roded --frontend qt [file ...]` открывает настоящее Qt desktop
окно. `--frontend curses` выбирает TUI явно. Выбор frontend не загружает другой
GUI toolkit; core можно использовать без обоих. Установка Qt dependency и
системных prerequisites документирована, curses-only запуск не требует рабочего
Qt display. Поддерживается опубликованный `qt` gem; абсолютный локальный путь
не должен стать обязательным для обычной установки.

В Qt работают те же buffers/windows, edits/undo, save/conflict prompts, поиск,
highlighting, REPL и picker. Modeline/minibuffer оформлены в одном Emacs-подобном
стиле с curses. Native widgets допустимы, но их text document и undo не становятся
второй авторитетной моделью: edits идут через core; результаты возвращаются в
widgets без feedback loop и потери point/selection/scroll. Учти преобразование
UTF-16 offsets Qt и принятой модели Unicode positions core.

Есть mouse focus/caret placement/selection, scrolling колёсиком и системный
clipboard для copy/paste. Эти действия также переводятся в core commands;
native context menu не обходит readonly, undo или modified state. Кнопка закрытия
desktop window использует тот же save/discard/cancel flow, что `C-x C-c`.
После отмены close окно остаётся рабочим. Resize, focus changes и picker/REPL
не отключают global keybindings.

Все обязательные Super aliases из `docs/keybindings.md` реально работают в Qt,
включая Alt+Super и Super с punctuation/Menu. `s-Left/s-Right` меняют ширину
активного split с допустимыми границами. Возможность назначить любую поддержанную
комбинацию через user keymap проверена. OS-reserved shortcuts отличать от ошибок
binding: проверить доставленные Qt events и отдельно физический ввод на desktop;
не менять глобальные hotkeys рабочего окружения без запроса пользователя.

Qt event loop и все widgets работают в GUI/main thread. Core transitions
сериализованы; доставка render snapshots в GUI thread явная, с ограниченной
очередью/объединением устаревших render updates. Не использовать существующий
`Application#run` без адаптации, если он создаёт main loop в background thread.
Проверить shutdown, exceptions и REPL interrupt без вызова Qt из чужого потока.

Для отсутствующих bindings сначала проверь generated API и native event payloads.
Постарайся реализовать рабочий обходной путь **в Roded Qt adapter**, как запросил
пользователь. Каждый workaround имеет `TODO(qt): HACK` с точным пробелом gem,
используемым обходом и планом замены после доработки `qt`; добавь регрессионную
проверку и запись в `docs/qt-workarounds.md`. Workaround не может оправдывать
data loss, гонки, неверный Super или фиктивно готовую функцию. Не смешивай
переписывание binding generator с этим goal и не редактируй чужие generated
build artifacts. Если безопасный обход действительно невозможен, предъяви
минимальный воспроизводимый пробел API и требуемую доработку пользователю.

## Архитектурные условия

- `Buffer` владеет текстом, metadata, revision/modified state и edit history;
  window/view владеет domain point/mark и выбором buffer. Устаревшее хранение
  единственного cursor в Buffer мигрируется последовательно.
- Editor session/state владеет buffers, views, active view, minibuffer/picker
  state и KillRing. Session принимает domain decisions. Handler работает с
  session и сервисами, а не с полным `Application` через `self`.
- Runtime/Application отвечает за boot, wiring, event loop, signals и cleanup.
  File IO, highlighting, picker providers и REPL имеют явные границы.
- Domain mutations сериализованы. Input events содержат источник; prefixes
  хранятся отдельно для независимых input streams. Page/scroll commands
  получают геометрию активного view, а не первого frontend в массиве.
- Различаются input facts, editor commands и UI updates. Quit меняет stop state
  core независимо от frontend acknowledgement; обычный quit с modified buffers
  сначала проходит save/discard/cancel flow. Signals и frontend EOF/failure
  имеют явную политику, не зависят от minibuffer focus. При signal/ошибке runtime
  гарантирует cleanup; не обещать интерактивное сохранение после fatal failure.
- Единый путь публикации UI-state после законченного перехода. Убрать прямые
  calls из Buffer в frontend и несогласованную смесь observers/broadcast/render,
  сохранив обновление каждого edit. Cross-thread данные — independent immutable
  snapshots, а не живые Hash/Array/String из модели.
- Viewport и physical layout — состояние представления конкретного view;
  общий geometry helper может быть независим от curses. Frontend не меняет
  текст, point, mark или history. Для custom scrolling используй явную policy
  core/view с геометрией: нельзя скрыть ошибку clamp экранного cursor.
- Core загружается и тестируется без подключения curses и Qt. Независимые views,
  позднее подключение frontend и восстановление initial UI-state проверяются.
- Не вводить CQRS/event sourcing, сетевую шину или универсальную plugin систему
  без требования конкретного обязательного сценария. FrontendManager —
  возможная деталь реализации, а не обязательный класс ради выполнения плана.

## Критерии завершения и доказательства

1. `bundle exec rake` проходит: specs и RuboCop. Не отключать lint целиком и
   не создавать blanket exclusions ради зелёного результата. Если отдельный
   лимит требует обоснованного изменения, документировать точечное решение.
2. Core specs покрывают контракты/invariants, source separation, view positions,
   undo/modified state, readonly и результаты сервисов. Integration specs
   проверяют законченные open/edit/save/close/quit и picker/REPL сценарии.
3. В PTY/терминале запускается настоящий `bin/roded` с curses; проверяются
   ввод, paste, resize, отображение окон, save и exit. Input/terminal state
   восстанавливается после normal quit, EOF/signal и ошибки runtime. Все
   потенциально зависающие tests имеют timeout и cleanup.
   Qt также проверяется с реальными widgets/offscreen integration, а затем в
   desktop display: ввод, Super combinations, split, highlighting, picker,
   REPL, save и window close/cancel. Widget doubles и synthetic modifier events
   не заменяют проверку живого GUI. Записать screenshots/observations, versions,
   display backend и результаты API probe; GUI-thread нарушения недопустимы.
4. Сквозной сценарий: открыть Ruby и второй текстовый файл; изменить оба;
   split windows; показать один документ в двух окнах; проверить независимые
   cursors и общий текст; переключить buffers; undo/redo; найти/заменить текст;
   save/save as; закрыть и заново открыть файлы; подтвердить точное содержимое.
   Выполнить сценарий в обоих frontend; общая семантика совпадает.
5. Проверены пустой файл, final newline, CRLF, кириллица, tabs, длинная строка,
   несколько файлов с одинаковым basename, read-only/error cases, внешний
   конфликт записи, отмена несохранённого quit и отказ от overwrite.
6. Проверены все picker providers и отмена preview; syntax highlighting после
   multiline edit и на незавершённом Ruby; REPL inspection/mutation, exception,
   interrupt и runtime registration команды, вызываемой через `M-x` и binding.
7. Проверен практический сценарий с файлом примерно на 10 000 строк и десятками
   buffers: ввод и навигация остаются пригодными к работе. Записать условия и
   наблюдения; искусственный benchmark framework не требуется.
8. README описывает установку, запуск, shortcuts, window/buffer semantics,
   настройку keymap, modes, picker, Ruby API/REPL и реальные ограничения.
   Документирует оба frontend, Super и Qt installation/workarounds.
   Нет обещаний реализованных collaboration/LSP. Validation document
   перечисляет команды, результаты, PTY/manual проверки и оставшиеся ограничения.
9. `PLAN.org` соответствует реальности, обязательных открытых пунктов не
   осталось; основные этапы закоммичены. Итог содержит commit list и способы
   запуска/проверки. Не утверждать «готово», если UI проверен только doubles.

Если внешняя среда не позволяет проверить настоящий TUI или desktop Qt,
сохрани реализацию и автоматические результаты, опиши конкретное ограничение и требуемый шаг
проверки. Такой результат не считать полностью подтверждённой готовностью.
Не сокращай обязательный scope и не заменяй функциональность заглушками для
завершения goal. Существенные изменения scope требуют решения пользователя.
