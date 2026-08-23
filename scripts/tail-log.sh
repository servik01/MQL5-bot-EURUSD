#!/usr/bin/env bash
# Живой просмотр CSV-лога советника.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f scripts/mt5.env ]]; then
  echo "Нет scripts/mt5.env — скопируй scripts/mt5.env.example и заполни пути." >&2
  exit 1
fi
# shellcheck source=/dev/null
source scripts/mt5.env

PATTERN="${1:-SMC_*.csv}"

FILE=$(find "$MT5_COMMON_FILES" -maxdepth 1 -name "$PATTERN" -print 2>/dev/null | head -1)
if [[ -z "$FILE" ]]; then
  echo "CSV-лог не найден в $MT5_COMMON_FILES" >&2
  echo "Советник создаёт его при первом запуске (InpWriteCsvLog = true)." >&2
  exit 1
fi

echo "Слежу за $FILE"
tail -f "$FILE"
