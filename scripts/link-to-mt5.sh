#!/usr/bin/env bash
# Связывает репозиторий с каталогом данных MT5 симлинками.
# После этого правки в Zed сразу видны MetaEditor'у — копировать ничего не нужно.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(pwd)"

if [[ ! -f scripts/mt5.env ]]; then
  echo "Нет scripts/mt5.env — скопируй scripts/mt5.env.example и заполни пути." >&2
  exit 1
fi
# shellcheck source=/dev/null
source scripts/mt5.env

if [[ ! -d "$MT5_DATA_DIR/MQL5" ]]; then
  echo "Не найден $MT5_DATA_DIR/MQL5 — проверь MT5_DATA_DIR в scripts/mt5.env" >&2
  exit 1
fi

link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    echo "  уже связано: $dst"
    return
  fi
  if [[ -e "$dst" ]]; then
    echo "  ВНИМАНИЕ: $dst существует и это не симлинк. Переименовываю в .bak"
    mv "$dst" "$dst.bak"
  fi
  ln -s "$src" "$dst"
  echo "  создано: $dst -> $src"
}

echo "Связываю с $MT5_DATA_DIR"
link "$REPO/MQL5/Experts/SMC" "$MT5_DATA_DIR/MQL5/Experts/SMC"
link "$REPO/MQL5/Include/SMC" "$MT5_DATA_DIR/MQL5/Include/SMC"
echo "Готово. В MetaEditor нажми F5 (обновить навигатор)."
