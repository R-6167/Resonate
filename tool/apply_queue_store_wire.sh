#!/usr/bin/env bash
# Applies tool/patches/queue_store_wire.patch to lib/providers/music_provider.dart
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/tool/patches/queue_store_wire.patch"
TARGET="$ROOT/lib/providers/music_provider.dart"
if [[ ! -f "$PATCH" ]]; then
  echo "Missing $PATCH" >&2
  exit 1
fi
if [[ ! -f "$TARGET" ]]; then
  echo "Missing $TARGET" >&2
  exit 1
fi
if grep -q "queue_store.dart" "$TARGET" && grep -q "QueueStore" "$TARGET"; then
  echo "music_provider.dart already appears wired to QueueStore — skipping patch"
  exit 0
fi
patch -p1 --batch --forward -d "$ROOT" < "$PATCH"
grep -q "class MusicProvider" "$TARGET"
grep -q "QueueStore" "$TARGET"
grep -q "queue_store.dart" "$TARGET"
echo "Patched $TARGET ($(wc -c < "$TARGET") bytes) — sanity checks passed"
