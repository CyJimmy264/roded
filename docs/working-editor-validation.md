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

### Qt окружение

- Установлен gem `qt` 0.1.9 (также доступна 0.1.8), системный Qt Widgets
  6.11.2, X display `:0`.
- Qt event/widget/runtime probes и реальный desktop smoke ещё не выполнены;
  это работа этапов 3 и 9.

### Ограничения этапа

File save здесь сохраняет текстовое представление, но ещё не использует
безопасную атомарную замену, revision tracking или conflict prompts. Эти сценарии
остаются открытыми до этапа 4.

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
