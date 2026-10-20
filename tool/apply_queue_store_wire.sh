#!/usr/bin/env bash
# Rebuild patch from base64 parts (if present), then apply to music_provider.dart
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="$ROOT/tool/patches"
PATCH="$PATCH_DIR/queue_store_wire.patch"
TARGET="$ROOT/lib/providers/music_provider.dart"

# Prefer assembling from b64 parts when present
if ls "$PATCH_DIR"/queue_store_wire.b64.* >/dev/null 2>&1; then
  TMP_B64="$(mktemp)"
  trap 'rm -f "$TMP_B64"' EXIT
  : > "$TMP_B64"
  for f in $(ls "$PATCH_DIR"/queue_store_wire.b64.* | sort); do
    tr -d '\n' < "$f" >> "$TMP_B64"
  done
  base64 -d < "$TMP_B64" > "$PATCH"
  echo "Rebuilt $PATCH from b64 parts ($(wc -c < "$PATCH") bytes)"
fi

if [[ ! -f "$PATCH" ]]; then
  echo "Missing $PATCH" >&2
  exit 1
fi
if [[ ! -f "$TARGET" ]]; then
  echo "Missing $TARGET" >&2
  exit 1
fi
if grep -q "queue_store.dart" "$TARGET" && grep -q "final QueueStore _queueStore" "$TARGET"; then
  echo "music_provider.dart already wired to QueueStore — skipping"
  exit 0
fi
patch -p1 --batch --forward -d "$ROOT" < "$PATCH"
grep -q "class MusicProvider" "$TARGET"
grep -q "QueueStore" "$TARGET"
grep -q "queue_store.dart" "$TARGET"
echo "Patched $TARGET ($(wc -c < "$TARGET") bytes) — ok"
