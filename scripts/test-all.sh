#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
REASONAIT=${REASONAIT:-reasonait}

for ext in "$ROOT"/extensions/*; do
    [ -f "$ext/extension.roc" ] || continue
    name=$(basename "$ext")
    echo "testing $name"
    $REASONAIT extension test "$ext"
done
