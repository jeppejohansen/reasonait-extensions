#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
REASONAIT=${REASONAIT:-reasonait}
OUT_DIR=${OUT_DIR:-"$ROOT/dist"}

mkdir -p "$OUT_DIR"

for ext in "$ROOT"/extensions/*; do
    [ -f "$ext/extension.roc" ] || continue
    name=$(basename "$ext")
    echo "building $name"
    $REASONAIT extension build "$ext" "$OUT_DIR/$name.wasm"
done
