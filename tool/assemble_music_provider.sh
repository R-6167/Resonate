#!/usr/bin/env bash
# Assembles lib/providers/music_provider.dart from tool/queue_store_chunks/part_*.b64
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/lib/providers/music_provider.dart"
DIR="$ROOT/tool/queue_store_chunks"
if [[ ! -d "$DIR" ]]; then
  echo "Missing $DIR" >&2
  exit 1
fi
: > "$OUT"
for f in $(ls "$DIR"/part_*.b64 | sort); do
  base64 -d < "$f" >> "$OUT"
done
echo "Assembled $OUT ($(wc -c < "$OUT") bytes)"
grep -q "class MusicProvider" "$OUT"
grep -q "QueueStore" "$OUT"
grep -q "queue_store.dart" "$OUT"
echo "Sanity checks passed"
