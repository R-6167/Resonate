#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/lib/providers/music_provider.dart"
DIR="$ROOT/tool/queue_store_chunks"
TMP_B64="$(mktemp)"
TMP_GZ="$(mktemp)"
trap 'rm -f "$TMP_B64" "$TMP_GZ"' EXIT
: > "$TMP_B64"
# Prefer v2_* (2KB) parts if present; else gz_part_*
if ls "$DIR"/v2_*.b64 >/dev/null 2>&1; then
  for f in $(ls "$DIR"/v2_*.b64 | sort); do
    tr -d '\n' < "$f" >> "$TMP_B64"
  done
else
  for f in $(ls "$DIR"/gz_part_*.b64 | sort); do
    tr -d '\n' < "$f" >> "$TMP_B64"
  done
fi
base64 -d < "$TMP_B64" > "$TMP_GZ"
gzip -dc "$TMP_GZ" > "$OUT"
echo "Assembled $OUT ($(wc -c < "$OUT") bytes)"
grep -q "class MusicProvider" "$OUT"
grep -q "QueueStore" "$OUT"
grep -q "queue_store.dart" "$OUT"
echo "Sanity checks passed"
