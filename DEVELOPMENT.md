# Разработка

## Идея workflow

Репозиторий — источник правды. Каталог данных MT5 ссылается на него симлинками,
поэтому копировать файлы после каждой правки не нужно: сохранил в Zed —
MetaEditor уже видит новую версию.

```
репозиторий (git, Zed)              каталог данных MT5
MQL5/Experts/SMC/     <--symlink--  MQL5/Experts/SMC/
MQL5/Include/SMC/     <--symlink--  MQL5/Include/SMC/
```

## Первичная настройка

```bash
cp scripts/mt5.env.example scripts/mt5.env
# заполнить пути под свою установку
./scripts/link-to-mt5.sh
./scripts/compile.sh
```

Найти каталог данных: в MT5 меню `Файл -> Открыть каталог данных`. На macOS под
CrossOver это путь внутри бутылки, вида
`.../Bottles/<имя>/drive_c/users/crossover/AppData/Roaming/MetaQuotes/Terminal/<HASH>`.
Если стоит нативный macOS-билд MT5 от MetaQuotes (не CrossOver) — это Wine-бутылка
`~/Library/Application Support/net.metaquotes.wine.metatrader5`, в портативном
режиме (`MQL5`/`config`/`Tester` лежат прямо внутри `Program Files/MetaTrader 5`).
Оба варианта в `scripts/mt5.env.example`.

`scripts/mt5.env` в git не попадает — пути у каждого свои.

Компиляция через `scripts/compile.sh` (wine CLI) в песочнице/трассируемом окружении
может зависать на диалоге "A debugger has been found running in your system" —
ложное срабатывание защиты MT5 от отладки на что-то похожее на дебаггер в песочнице.
Если так — компилировать вручную в открытом MetaEditor (`F7`), это работает надёжно.

## Задачи Zed

`.zed/tasks.json` содержит четыре задачи, вызываются через палитру команд
(`cmd-shift-p` -> `task: spawn`):

| Задача | Что делает |
|---|---|
| `MT5: compile EA` | компилирует основной советник |
| `MT5: compile current file` | компилирует открытый файл |
| `MT5: link into data folder` | пересоздаёт симлинки |
| `MT5: tail CSV log` | живой просмотр лога советника |

Удобно повесить компиляцию на горячую клавишу в `~/.config/zed/keymap.json`:

```json
[
  {
    "context": "Workspace",
    "bindings": {
      "cmd-b": ["task::Spawn", { "task_name": "MT5: compile EA" }]
    }
  }
]
```

## Про подсветку

Полноценного LSP для MQL5 нет. `.zed/settings.json` подсовывает C++ — подсветка
и навигация по скобкам работают, автодополнение по функциям MQL5 (`iHigh`,
`CopyBuffer`, `SymbolInfoDouble`) — нет. Справка по функциям остаётся в
MetaEditor по `F1`.

## Цикл работы

1. Правка в Zed.
2. `MT5: compile EA` — ошибки приходят прямо в терминал Zed.
3. Тестер стратегий в MT5 (не забыть `Обновить` в навигаторе, если менялся список входов).
4. Разбор `SMC_<символ>_<magic>.csv` из `Common\Files`.
5. Коммит.

## Стиль кода

Отступ 3 пробела, строка до 100 символов — как в стандартной библиотеке MQL5,
чтобы диффы с примерами MetaQuotes читались одинаково. `.editorconfig` это держит.

Именование: `Inp*` для входных параметров, `g_*` для глобальных, `m_*` для полей
класса, `C*` для классов, `S*` для структур, `ENUM_SMC_*` для перечислений.

## Логи

Советник пишет CSV в `Common\Files` (не в `MQL5\Files` — так лог общий для всех
терминалов и переживает переустановку). Формат: `time;event;details`.

События: `EA_INIT`, `PENDING_PLACED`, `SIGNAL_REJECTED`, `PENDING_EXPIRED`,
`PENDING_CANCELLED`, `FILLED`, `CLOSED`, `POSITION_CLOSED`, `REQUEST_FAILED`.

Основная метрика первого прогона — отношение `FILLED` к `PENDING_PLACED`:

```bash
awk -F';' '{print $2}' SMC_EURUSD_20260823.csv | sort | uniq -c | sort -rn
```

## Ветки

`main` — то, что компилируется и прогонялось в тестере.
`feat/<что>` — эксперименты с логикой. Каждая гипотеза отдельной веткой,
чтобы можно было сравнить отчёты тестера между ветками.
