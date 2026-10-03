# Qt frontend: исходные данные и контракт реализации

Это дополнение к `GOAL.md`, не готовая реализация. Пользователь явно включил
Qt frontend, Super shortcuts и допустил локальные hacks при пробелах своего
gem, с обязательным TODO о будущей доработке Qt.

## Источники и подтверждённая поверхность API

3 октября 2026 года прочитаны:

- `/home/mveynberg/Code/Ruby/qt/README.md`, gemspec и Ruby/runtime sources;
- generated widgets/constants/event payload schemas в локальном `qt/build`;
- `/home/mveynberg/Code/Ruby/qtimetrap/lib/qtimetrap.rb`, container и примеры
  использования событий/timers в `app/views` / `app/components`.

На момент первоначального probe использовался gem **0.1.9**. Сейчас Roded
зависит от **qt ~> 0.2.0**; исправления binding и удалённые обходы перечислены
в `docs/qt-workarounds.md`. Для API поведения ориентироваться на runtime probe
и integration specs установленной версии.

В локальных sources есть `QApplication`, `QTimer`, `QShortcut`,
`QPlainTextEdit`, `QTextEdit`, `QTextCursor`, `on(:key_press)` и subscriptions
через `connect`. Key payload schema включает `key`, `text`, `modifiers`,
`is_auto_repeat`. Event handler может вернуть `:consume` для перехвата события.
Constants включают Control/Alt/Shift/MetaModifier.

Однако наличие класса не означает полноту его binding. Например, native text
cursor/format/extra-selection API и virtual overrides следует проверять по
доступным методам и тестам, а не по полной документации C++ Qt. Здесь Qt API
не запускался и не компилировался, это проверка sources.

Qt различает AltModifier и MetaModifier; см.
[Qt keyboard modifiers](https://doc.qt.io/qt-6/qt.html#KeyboardModifier-enum).
В Roded на Linux: Emacs `M-` = Alt, Emacs `s-` = Super / Qt MetaModifier.
Не потерять это различие при использовании QKeySequence, где имя Meta имеет
собственное Qt значение. Кейсы Alt+Super, Ctrl+Super, Shift+Super и punctuation
проверить отдельными примерами, включая `M-s-j`, `s-l`, `s-,`, `s-.`.

`qtimetrap` — пример рабочего boot/event/style слоя, не шаблон структуры Roded.
Полезны `app.exec`, `QTimer`, Ruby subscriptions и раздельные view models;
DI framework, Rails-like layout и polling каждого domain объекта копировать
не требуется. Политика hacks из чужого AGENTS.md не распространяется на Roded:
пользователь специально разрешил обходы здесь. Исходные проекты остаются
справочниками; основной результат и коммиты создаются в Roded.

## Ранний API probe и вертикальный сценарий

До реализации полного Qt UI проверить минимальным воспроизводимым приложением:

1. QApplication/window lifecycle и GUI thread.
2. Key/text/modifier events, consume, repeat, Unicode и punctuation.
3. Реально доступные способы рисовать текст, spans, cursor, selection и scroll.
4. Resize/focus/close, возможность отменить close.
5. Доставку UI-state из core через GUI-thread scheduling, без deadlocks.

Итог probe — небольшой работающий Roded Qt slice: открыть один buffer,
ввести текст через core, увидеть update, вызвать test command с Super,
корректно закрыть окно. Не отложить эту проверку до конца переписывания core.
Prototype затем либо интегрировать, либо удалить; не оставлять вторую editor
implementation и второй state store.

## Границы модели и widgets

Native text widgets можно использовать как presentation. Их default editing,
native undo, context menu и shortcuts не должны изменять документ в обход core.
Выбрать один проверяемый способ input translation/snapshot application;
подавлять render feedback loops. Не делать постоянный sync двух независимых
авторитетных документов через timer. При readonly display/custom drawing
реализовать реальный cursor, selection, copy/paste и accessibility/focus basics
в пределах минимального GUI, не выдавать статический QLabel за editor.

Qt callbacks/widgets/QApplication живут в GUI/main thread. Core может владеть
отдельным потоком или последовательно выполняться в GUI dispatcher, но это
должно быть явно определено вместе с REPL execution/interrupt policy. Старый
runtime, вызывающий каждый frontend.handle_command из background main loop,
для Qt без адаптации непригоден. Marshal snapshots через поддерживаемый
dispatcher или bounded QTimer mailbox; timer здесь — integration detail,
а не domain polling/новая event bus.

В обязательном объёме — один frontend за запуск с общим core. Одновременный
Qt+curses в одном процессе не требуется, но типы событий и snapshots допускают
несколько независимых источников. OS desktop frame и Roded editor window/split
должны называться различно в коде и документации.

## Workarounds

Missing API сначала подтвердить в **используемой версии** gem: available methods,
generated sources, runtime payload, минимальный reproducer. Затем выбрать
наименьший рабочий workaround в `lib/roded/frontends/qt` или его support слоях.
Предпочесть поддержанный альтернативный widget/API и Ruby adapter. Если нужен
низкоуровневый обход, изолировать его с guards по версии/ABI, проверкой lifetime
и регрессионным test; не размазывать raw pointers/FFI по editor core.

Обязательная форма комментария рядом с обходом:

```ruby
# TODO(qt): HACK — qt <version> does not expose <exact API/capability>.
# Workaround: <what this code does and its constraints>.
# Extend qt with <required binding/runtime support>, then replace this with <normal API>.
```

При создании первого workaround добавить `docs/qt-workarounds.md`: место кода,
version/API gap, reproducer, workaround, ограничения, test и способ удаления.
Документ не нужен пустым ради галочки. TODO допустимы к завершению goal,
если обязательная функция реально работает и проверена. TODO вместо функции
или suppress ошибки с fake success не удовлетворяют goal.

Не менять installed gem/global config или чужой репозиторий как скрытую часть
сборки. Local dependency override допустим как документированный development
вариант; обычная установка должна быть воспроизводима с опубликованным gem.
Нативное приложение не должно crash из-за незафиксированного ABI предположения.
При действительно невозможном обходе сохранить reproducer и конкретный запрос
к binding; не подменять Qt другим GUI toolkit.

## Проверка готовности

Общий acceptance scenario из GOAL выполняется в curses и Qt. Для Qt дополнительно:
real-widget offscreen integration, живой desktop smoke, физические Super keys,
Alt/Super distinction, mouse caret/selection/wheel, clipboard, close cancellation,
Unicode offset conversion, native editing interception и exception shutdown.
Зафиксировать Qt/gem/backend versions, результаты probes и screenshots.
Offscreen modifiers доказывают input translation; физические shortcuts отдельно
доказывают доставку events в пользовательском окружении.

Clipboard использует `QApplication.clipboard.text`/`set_text`, caret ставится
через `QTextCursor` с переводом core codepoint column в UTF-16 offset, split
ratio применяется через `QSplitter.set_sizes`, а отмена native close
возвращает `:reject`. Детали и regression specs — в
`docs/qt-workarounds.md`. Наличие этих API не закрывает оставшиеся acceptance
checks. Qt caret отображается контрастным block поверх символа; строка с point
получает приглушённую фоновую подсветку. Mouse press/drag/release hit-test-ятся
по реальному QTextEdit, переводятся обратно в core point/mark и повторно
рендерятся из общего snapshot. Изолированный Xvfb smoke проверяет mouse
selection/copy, wheel, edit/save, split и synthetic Super events; физические
Super shortcuts отдельно проверяются на desktop.
