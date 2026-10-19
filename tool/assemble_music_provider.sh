#!/usr/bin/env bash
# Assembles lib/providers/music_provider.dart from tool/queue_store_chunks/part_*.txt
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/lib/providers/music_provider.dart"
DIR="$ROOT/tool/queue_store_chunks"
if [[ ! -d "$DIR" ]]; then
  echo "Missing $DIR" >&2
  exit 1
fi
: > "$OUT"
for f in $(ls "$DIR"/part_*.txt | sort); do
  cat "$f" >> "$OUT"
done
echo "Assembled $OUT ($(wc -c < "$OUT") bytes)"
# Sanity checks
grep -q "class MusicProvider" "$OUT"
grep -q "QueueStore" "$OUT"
grep -q "queue_store.dart" "$OUT"
echo "Sanity checks passed"
