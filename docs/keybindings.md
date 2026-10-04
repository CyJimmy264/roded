# Keybindings Roded 0.2.0

Клавиатура, M-x и Ruby API используют общий реестр команд. Таблицы описывают
стандартные bindings; пользовательская конфигурация может их переопределить.
`C-h b` / `M-x describe-bindings` показывают фактическую конфигурацию.

## Основные bindings

| Клавиши | Команда / поведение |
| --- | --- |
| `C-x C-f` | Find file: путь/completion/новый файл |
| `C-x C-s`, `F7` | Save; запрос пути, если имя ещё не задано |
| `C-x C-w` | Save as |
| `C-x C-c` | Quit с save/discard/cancel для edits |
| `C-x b` | Buffer picker |
| `C-x <left>`, `C-x <right>` | Previous / next buffer в активном окне |
| `C-x k` | Kill current buffer с проверкой modified state |
| `C-x 2`, `C-x 3` | Split сверху/снизу и слева/справа |
| `C-x o`, `C-x 0`, `C-x 1` | Other window, delete window, delete other windows |
| `C-f/C-b`, Left/Right | Следующий/предыдущий символ |
| `C-n/C-p`, Down/Up | Следующая/предыдущая строка |
| `M-f/M-b` | Следующее/предыдущее слово |
| `C-a/C-e`, Home/End | Начало/конец строки |
| `M-</M->` | Начало/конец документа |
| `C-v/M-v`, PageDown/PageUp | Page down/up по размеру активного окна |
| Backspace, `C-d`/Delete, Enter | Удаление назад/вперёд, newline |
| Tab | Минимальный indent; сохранять предсказуемую семантику tabs |
| `C-/`, `C-_`, `C-x u` | Undo; разные terminal aliases одной команды |
| `C-?`, `C-c r d`, `M-x redo` | Redo; terminal fallback sequence |
| `C-SPC` / `C-@` | Set mark |
| `C-w`, `M-w`, `C-y` | Kill region, copy region, yank |
| `C-k` | Kill до EOL / newline на EOL |
| `M-y` | KillRing picker; после yank заменяет предыдущую вставку |
| `C-s` | Line picker текущего buffer, по vanilla consult-line |
| `M-x isearch-forward`, `M-x isearch-backward` | Поиск вперёд/назад |
| `M-g g` | Goto line |
| `M-%` | Query replace |
| `M-x` | Command picker |
| `C-g` | Cancel prefix/prompt/picker/search/selection |
| `C-h b`, `M-x describe-bindings` | Справка по bindings |
| `C-c p f` | Project/root file picker |
| `C-c r r`, `M-x ruby-repl` | Встроенный Ruby REPL |
| `C-c C-c`, `C-c C-k` | Выполнить ввод REPL / прервать выполняющийся Ruby-код |
| `C-c C-p`, `C-c C-n` | Предыдущая / следующая команда в истории REPL |

В picker: `C-n/C-p`, Up/Down перемещают выбор, `M-p/M-n` листают историю query,
Enter принимает, `C-g` отменяет; обычный ввод меняет query, Backspace/Delete
редактируют query. В prompts текстовые editing keys имеют предсказуемое
поведение. Context keymaps не перехватывают global cancel и системное завершение
runtime.

В Qt clipboard использует `C-S-c` для copy region, `C-S-x` для cut region и
`C-S-v` для paste. Они проходят через core region/`:paste` действия; `C-v`
остаётся page-down, как в curses.

## Минимальное подмножество личных Spacemacs bindings

`s-` в Lisp означает **Super**, `M-` — **Meta/Alt**; `M-s-j` означает
Alt+Super+j, а не `Esc s j`. Не подменять эту нотацию другой последовательностью
молча. Большинство обычных терминалов не передаёт Super/Menu и некоторые
Ctrl+Shift chords. Все обязательные действия должны быть доступны через
обычные terminal bindings и `M-x`. Curses запрашивает Kitty CSI-u keyboard
reporting, чтобы различать сочетания вроде `C-?` и Backspace; если терминал его
не поддерживает, используйте terminal fallback `C-c r d` для redo. В curses
Super/Menu aliases применяются при наличии соответствующего нормализованного
input token.
В **Qt frontend** перечисленные ниже Super/Menu aliases обязательны.
На Linux Qt MetaModifier переводится в Emacs `s-`, AltModifier — в `M-`;
Ctrl/Shift/Super и punctuation сохраняются при нормализации. Проверяются raw
events и фактическое выполнение команд. OS может перехватить shortcut до Qt:
такой случай документируется отдельно от возможностей приложения.

| Исходный binding | Поведение | Доступный fallback |
| --- | --- | --- |
| `F7`, `M-s-j` | Save buffer | `C-x C-s` |
| `M-s-k` | Kill current buffer | `C-x k` |
| `M-s-c` | Delete current window | `C-x 0` |
| `s-w` | Next window | `C-x o` |
| `s-Left`, `s-Right` | Уменьшить/увеличить ширину активного split в Qt | `M-x shrink-window-horizontally/enlarge-window-horizontally` |
| `C-<`, `C->` | Previous / next buffer | `C-x <left>/<right>` |
| `s-,`, `s-.` | Previous / next buffer; без project perspectives | `C-x <left>/<right>` |
| `M-p`, `M-n` | Scroll up/down на строку | Те же bindings; `M-x scroll-line-up/down` |
| `M-P`, `M-N` | Scroll up/down на страницу | Те же bindings; `M-x scroll-page-up/down` |
| Menu | Project/root file picker | `C-c p f` |
| `M-Menu` | Picker всех открытых buffers | `C-x b` |
| `s-l` | Выделить текущую строку | `C-c l`, `M-x select-current-line` |
| `M-s-u` | Untabify region, при отсутствии region — buffer | `M-x untabify` |
| `M-s-Tab` | Tabify region, при отсутствии region — buffer | `M-x tabify` |
| `M-s-d`, leader `ddd` | Вставить дату/время `%d/%m/%Y %H:%M:%S` | `C-c d d`, `M-x insert-current-date-time` |
| `M-s-t`, leader `ddt` | Вставить время `%H:%M:%S` | `C-c d t`, `M-x insert-current-time` |
| `M-s-b` | Новая строка с `binding.irb` после текущей, с её отступом | `C-c r b`, `M-x insert-binding-irb` |

Scroll-команды определяются явно: сдвигают viewport активного окна и point
с сохранением экранной строки, насколько позволяют границы документа. Это
отдельные команды от обычного перемещения point/page movement. Расчёт делается
через core/view policy с геометрией окна; frontend не мутирует domain point.

Leader aliases из Spacemacs отражены terminal sequences, не требуют Evil/SPC
mode. `insert-binding-irb` только вставляет текст в редактируемый файл; встроенный
REPL открывается через `ruby-repl` и не зависит от этой команды.
Время вставляется в локальной timezone процесса; это документируется.

## Не реализованные подсистемы

LSP, Magit, макросы, Org, folding, структурное редактирование, project perspectives,
completion и sidebar не входят в 0.2.0. Для них нет bindings-заглушек.
