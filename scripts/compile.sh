#!/usr/bin/env bash
# Компиляция через metaeditor64 в консольном режиме.
# metaeditor возвращает количество ошибок, лог кладёт рядом с исходником.
set -uo pipefail

cd "$(dirname "$0")/.."
REPO="$(pwd)"

TARGET="${1:-MQL5/Experts/SMC/SMC_PinSweep_EA.mq5}"

if [[ ! -f scripts/mt5.env ]]; then
  echo "Нет scripts/mt5.env — скопируй scripts/mt5.env.example и заполни пути." >&2
  exit 1
fi
# shellcheck source=/dev/null
source scripts/mt5.env

if [[ ! -f "$REPO/$TARGET" ]]; then
  echo "Не найден файл: $REPO/$TARGET" >&2
  exit 1
fi

# metaeditor работает с путями внутри каталога данных, поэтому компилируем
# через симлинк, а не напрямую из репозитория.
REL="${TARGET#MQL5/}"
WIN_TARGET="$MT5_DATA_DIR/MQL5/$REL"

if [[ ! -e "$WIN_TARGET" ]]; then
  echo "Файл не виден из каталога данных MT5." >&2
  echo "Запусти сначала ./scripts/link-to-mt5.sh" >&2
  exit 1
fi

LOG="${WIN_TARGET%.*}.log"
rm -f "$LOG"

echo "Компилирую $REL ..."
if [[ -n "${WINE_CMD:-}" ]]; then
  "$WINE_CMD" "$METAEDITOR" /compile:"$WIN_TARGET" /log:"$LOG" >/dev/null 2>&1
else
  "$METAEDITOR" /compile:"$WIN_TARGET" /log:"$LOG" >/dev/null 2>&1
fi
STATUS=$?

if [[ -f "$LOG" ]]; then
  # MetaEditor пишет лог в UTF-16LE
  iconv -f UTF-16LE -t UTF-8 "$LOG" 2>/dev/null || cat "$LOG"
else
  echo "Лог не создан — проверь METAEDITOR и WINE_CMD в scripts/mt5.env" >&2
fi

if [[ $STATUS -eq 0 ]]; then
  echo "OK: ошибок нет"
else
  echo "Ошибок компиляции: $STATUS"
fi
exit $STATUS
