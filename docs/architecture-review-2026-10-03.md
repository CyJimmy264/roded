# Ревизия ветки `1-architecture`

Дата: 3 октября 2026 года. Проверен локальный HEAD `c134459`, база сравнения —
`develop` / `cc7d39f`. На начало проверки рабочее дерево было чистым.
Ревизия не меняет реализацию и не переписывает `PLAN.org`.

## Вывод

Ветку стоит продолжать. Вынос маршрутизации в core, независимый Minibuffer,
перенос page movement из curses и появление тестов — полезные изменения.
Откатывать их целиком оснований нет. Но план пока представляет собой список
выделяемых классов, а не завершённую архитектуру: не определены контекст ввода,
способ публикации состояния, гарантии завершения и граница session/view.

Следующий шаг — исправить эти контракты и закрыть несколько наблюдаемых ошибок.
Механическое выделение `EditorState`, `FileService`, `FrontendManager` сейчас
разнесёт существующие зависимости по новым файлам, но не устранит их.

## Что уже сделано

В ветке восемь коммитов относительно `develop`: начальный план от 21 декабря
2025 года и семь последующих коммитов от 13 марта 2026 года. Последний шаг —
перенос page up/down в core. `EditorState`, `FileService` и `FrontendManager`
ещё не реализованы.

| Решение | Оценка |
| --- | --- |
| Keymap resolution и префиксы в `CommandRouter` | Сохранить; добавить контекст потока ввода |
| `CommandHandler` отдельно от main loop | Сохранить; убрать зависимость от всего `Application` |
| `Minibuffer` как независимая модель | Сохранить |
| Page up/down изменяют cursor в core | Сохранить; размер страницы брать из источника команды |
| Только core меняет модель | Сохранить и сделать проверяемым контрактом |
| Маленькие этапы с тестами | Сохранить; тестировать завершённые сценарии, а не только отправку сообщений |
| File IO за отдельной границей | Сохранить; сначала определить точность загрузки/сохранения |

## Проверки

`bundle exec rake` выполнен на Ruby 3.4.2:

- RSpec: **28 examples, 0 failures**.
- RuboCop: **70 offenses**, итоговый код возврата `rake` — **1**.

Дополнительно выполнены отдельные Ruby-пробы с FakeFrontend, настоящим
`CommandRouter` / `Application` и curses adapter с подставным экраном.
Проверялись core main loop, пустой файл, open/save, прокрутка, ввод от разных
источников и подключение frontend после открытия файла. Полноценный интерактивный
TUI в настоящем терминале в этой ревизии не проверялся.

Зелёные specs — полезная база, но утверждение о стабильном happy path слишком
сильное. Application specs подставляют `@frontends` напрямую и вызывают
`handle_event`; FakeFrontend не реализует input loop, close и observers.
Тест `M-x quit` проверяет наличие сообщения `:quit`, но не завершение `run`.
Отдельного welcome/lifecycle smoke test нет. Не проверены также ошибки файловых
операций и сохранение прочитанного текста без изменений.

## Подтверждённые проблемы

### 1. P1: core зависит от обратного `:quit` из frontend

Источники:
[Application#handle_event](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/application.rb:108),
[main_loop](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/application.rb:220),
[обработчик quit](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/command_handler.rb:49),
[curses wake-up](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/frontends/curses.rb:89).

В очередь попадает `Event(:key)`. Router превращает `C-x C-c` в `Event(:quit)`
внутри `handle_event`, но main loop проверяет исходный event, который остался
`:key`. Handler лишь отправляет frontend-команду `:quit`. Curses просыпается,
возвращает новый `Event(:quit)`, и только после этого core выходит из цикла.

Проба: после двух key events FakeFrontend получил `:quit`, а core main loop
остался ждать очередь. Явное добавление `Event(:quit)` завершило его.
В обычном curses этот обходной путь может успешно работать; проблема именно
в том, что завершение core не является самостоятельным контрактом.

`M-x quit` уже зависел от такого ответа в `develop`. После переноса router
зависимость распространилась и на `C-x C-c`. При minibuffer focus routed quit
вообще игнорируется. `:signal` от HUP/INT/QUIT/TERM также не обрабатывается:
проба TERM не породила quit. Обработка сигналов отсутствовала и в базе.

Исправление: quit меняет состояние выполнения core независимо от UI; затем
runtime останавливает input loops, дожидается потоков и освобождает ресурсы.
Системные события обрабатываются до выбора buffer/minibuffer focus.
`run` нуждается в `ensure`; ошибка команды сейчас может обойти закрытие curses.
Установку и восстановление process signal handlers следует привязать к runtime,
а не к каждому `Application.new`.

### 2. P1: пустой файл нарушает инварианты Buffer; save меняет исходный текст

Источники:
[open_file](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/application.rb:135),
[Buffer#insert_char](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/buffer.rb:32),
[Buffer#to_s](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/buffer.rb:137).

`File.read(...).lines.map(&:chomp)` для пустого файла даёт `[]`, хотя новый
Buffer начинается с одной пустой строки. После открытия вставка `a` падает:
`NoMethodError: undefined method 'insert' for nil`. В `run` это может завершить
main thread с исключением до cleanup.

Отдельно проверен roundtrip: `"alpha\nbeta\n"` после open/save становится
`"alpha\nbeta"`. Это потеря завершающего перевода строки, даже без редактирования.
Обе ошибки унаследованы из `develop`.

До выделения FileService нужны инварианты: хотя бы одна строка, допустимые
row/col, контролируемое изменение содержимого, сохранение final newline.
Политику CRLF и encoding следует явно определить; текущее `chomp` уже
нормализует окончания строк. Удаление только setter `cursor_pos=` недостаточно:
возвращаемый Hash и массив `lines` остаются изменяемыми снаружи.

### 3. P1: при нескольких frontend ввод теряет свой источник

Источники:
[единственный router](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/application.rb:21),
[pending prefix](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/command_router.rb:3),
[page_size](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/application.rb:167).

Один `@pending_prefix` теперь общий для всех frontend. Проверено: `C-x` от A
и `C-c` от B складываются в quit. До выноса router префикс был локальным для
каждого экземпляра curses. Вынос правильный, но состояние последовательности
должно оставаться отдельным для каждого независимого потока ввода.

Page size берётся из первого зарегистрированного frontend. Проверено:
при высотах страниц 3 и 8 команда от второго frontend сдвигает cursor на 3.
Это новое ограничение последнего коммита.

Нужен source/input-stream id; при разных views — ещё и view id. Router хранит
pending state по input stream, а handler использует геометрию инициировавшего
view. Подмена source в payload сама по себе ничего не решает: текущий core
этот контекст не читает.

### 4. P2: три пути обновления UI дают разные гарантии

Источники:
[Buffer observers](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/buffer.rb:28),
[move handler](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/command_handler.rb:17),
[curses update](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/frontends/curses.rb:62),
[frontend-команды](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/frontends/curses.rb:110).

Текстовые изменения рисуются через observers. Перемещение дополнительно
рассылает `:move_cursor` / `:render`. Open вызывает frontend.render напрямую;
focus и сообщения передаются ещё отдельными методами.

На Down сначала observer делает ensure-visible/redraw, затем `:move_cursor`
вызывает `scroll_down` и ещё redraw. Проверено на экране высотой 4: из row 0
получаем row 1 и top 1, хотя cursor и так был виден при top 0. Это поведение
было и в `develop`, но оно не согласовано с предполагаемой общей policy.

Если просто удалить observers по плану, insert/backspace/delete/newline
перестанут обновлять экран: handler не отправляет для них render.
Унификацию публикации изменений следует поднять с P3 до этапа перед выносом state.

Рекомендуемый конечный путь: core завершает команду, публикует состояние для UI,
adapter вычисляет viewport и рисует. На этапе миграции нужны проверки, что
все изменения по-прежнему доходят до frontend. Не требуется вводить event
sourcing или сложную шину сообщений.

### 5. P2: frontend хранит отдельный current buffer без начальной синхронизации

Источники:
[add_frontend](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/application.rb:57),
[curses add_buffer](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/frontends/curses.rb:43).

Проверено: welcome → открыть файл → подключить curses adapter. Core редактирует
файл, а новый adapter выбирает первый переданный buffer, то есть welcome.
`add_frontend` передаёт список buffers, но не активный buffer и minibuffer state.
Это унаследованная проблема; новый frontend должен получать полное текущее
состояние до начала чтения input.

### 6. P2: видимость cursor пока гарантируется только частично

Источник:
[ensure_cursor_visible / place_cursor](/home/mveynberg/Code/Ruby/CyJimmy264/roded/lib/roded/frontends/curses.rb:256).

При длине строки 26 и ширине экрана 12 `C-e` даёт domain col 26, но экранный
cursor принудительно ставится в col 11. Горизонтального viewport или wrapping
нет; пользователь не видит реальную позицию редактирования. Также page size
использует maxy−1, а vertical visibility и рисование — maxy; последняя строка
может одновременно считаться строкой текста и строкой minibuffer/message.
Эти ограничения необходимо учесть в обещании «cursor всегда виден».

## Какие положения плана пересмотреть

1. **Не переносить viewport целиком в EditorState.** Core отвечает за допустимую
   позицию cursor и смысл команды. Конкретный viewport зависит от размеров,
   wrapping, overlays и frontend. Общий алгоритм ensure-visible можно сделать
   независимым от curses helper, но применять к состоянию конкретного view.
   План сейчас одновременно отдаёт viewport frontend и его policy core, не
   определяя обмен геометрией и индивидуальные views.

2. **Не переносить `clamp_cursor_into_view`: его уже удалили.** Последний коммит
   убрал именно мутацию cursor из curses. Соответствующий незакрытый пункт плана
   устарел. Дальше нужны проверки отсутствия мутаций и исправление view policy.

3. **Не делать EditorState новым центром всего приложения.** Состояние session
   и его инварианты можно хранить там; выполнение команд остаётся в handler,
   file IO — за адаптером, lifecycle — в runtime. Текущий `CommandHandler.new(self)`
   лишь переносит case в другой файл: он всё ещё зависит от Application,
   frontend broadcast, page size, File IO и minibuffer orchestration.

4. **Определить session/view до расширения multi-frontend.** Минимальная первая
   модель: одна session с общими current buffer, cursor и minibuffer; несколько
   отображений с разными viewport и потоками ввода. Это соответствует текущему
   поведению с явными ограничениями. Если нужны независимые окна/пользователи,
   current buffer, focus и cursor должны принадлежать отдельному editor view,
   а Buffer — общему документу. Одного глобального EditorState тогда мало.
   Сейчас реализовывать оба варианта не требуется.

5. **Сначала исправить lifecycle, затем выделять FrontendManager.** Гарантии
   shutdown нужны на P1. Отдельный класс менеджера можно по-прежнему отложить:
   сам по себе он не исправляет зависимость quit от frontend acknowledgement.

6. **Сохранить различие сообщений, не усложняя механизм.** Input Event описывает
   key/signal/disconnect/geometry и источник; EditorCommand — намерение core;
   UI update — состояние или инструкция adapter. Сейчас первые две роли
   обе представлены Event, а Command обозначает UI-инструкцию. Имена надо
   согласовать, но переименование без изменения потока ничего не исправит.
   `Data.define` не делает вложенные payload Hash/Array/String неизменяемыми.

7. **Убрать лишние зависимости, когда закреплён контракт.** Frontend больше
   не использует Keymap, поэтому setter из Application и accessor в curses
   не нужны. `require "roded"` всё ещё безусловно грузит curses; adapter следует
   подключать в launcher отдельно, чтобы core был загружаем без curses.

8. **Программируемость требует небольшого отдельного решения.** Keymap сегодня
   ссылается на фиксированный набор символов, M-x использует отдельный case,
   произвольные multi-key prefixes не поддерживаются: `C-c a` возвращает noop
   и insert, а не команду. До расширения bindings нужен общий контракт вызова
   команд из клавиатуры, M-x и Ruby API. Регистрацию команд можно ввести позже,
   когда появится первый реальный сценарий расширения. Plugin framework,
   hot reload и collaboration не нужны для завершения этой миграции.

9. **Window/StatusBar требуют решения по назначению.** Текущие классы печатают
   в stdout и не участвуют в curses UI. Их console-реализацию можно убрать;
   это не означает отказа от будущей сущности editor view/window.

## Рекомендуемый минимальный контракт

- Один поток core последовательно выполняет команды и меняет domain state.
- Каждый независимый input stream имеет свой pending prefix.
- Геометрия и source команды явно известны core; page size не выбирается по
  порядку регистрации frontend.
- Quit устанавливает stop state core. Input worker прекращается по stop/wake,
  runtime дожидается worker и затем освобождает ресурсы; cleanup работает и
  при исключении. Потеря одного frontend и завершение всей session различаются.
- Handler зависит от session/state и FileService, но не от curses/Application.
- Core после завершения команды публикует UI-состояние. Frontend не вызывается
  напрямую из Buffer и не изменяет domain objects.
- Если render выполняется в потоке frontend, передаются независимые immutable
  snapshots; нельзя пересылать живые массивы строк и cursor Hash. Если render
  пока синхронный в core, это тоже надо явно закрепить. Queue сама по себе
  защищает только доставку сообщений, а не все передаваемые объекты.
- Viewport принадлежит конкретному представлению. Проверяемая policy учитывает
  доступные строки/столбцы и overlays и сохраняет реальную видимость cursor.
- FileService отвечает за IO/result/error; core решает, какой buffer активировать
  и какое сообщение показать. Первая версия может быть синхронной: асинхронность
  и протокол устаревших results пока не оправданы.

## Порядок дальнейшей работы

| Этап | Содержание | Критерий завершения |
| --- | --- | --- |
| 1 | Quit/signals/cleanup; пустой файл и final newline | Core самостоятельно завершает цикл; текст проходит open/save без потерь |
| 2 | Зафиксировать session/view, source и message contracts | Два input stream не смешивают prefixes; page movement использует исходный view |
| 3 | Унифицировать публикацию UI; согласовать viewport | Все виды edits видны; initial sync отражает current state; движение не имеет второй scroll-команды |
| 4 | Ввести EditorState и отвязать handler от Application | Domain state и command flow тестируются без runtime и curses |
| 5 | Вынести FileService | IO ошибки имеют явные results и не скрывают ошибки render/observer |
| 6 | Упростить runtime; при необходимости FrontendManager | Start/stop/disconnect/exception имеют проверяемое завершение |
| 7 | Cleanup, docs, единый вызов команд из Ruby/M-x/keymap | Core загружается без curses, роли отражены в документации |

Каждый этап — отдельные небольшие изменения. Не стоит откладывать все проверки
до завершения этапа: lifecycle specs нужны в первом, source specs — во втором,
а observer-путь удаляется только вместе с сохранением обновления всех edits.

Для lint следует либо устранить замечания, либо отдельно согласовать ограниченный
baseline существующего долга и запретить его рост. Проход RSpec нельзя обозначать
как проход `rake`. Разбивать методы только ради лимитов RuboCop не является
архитектурной целью.

Минимальные дополнительные сценарии: run с routed quit и M-x quit без обратного
UI-event; signal во время minibuffer; cleanup при исключении; пустой файл;
final newline roundtrip; два input stream; разные view sizes; позднее подключение
frontend; отражение insert/delete/newline; видимость cursor на длинной строке.

До этих изменений ветка — полезный промежуточный рефакторинг. После них появится
проверяемая основа для дальнейшей архитектуры, без обязательного большого
переписывания или преждевременной инфраструктуры.
