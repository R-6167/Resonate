#!/usr/bin/env bash
# Assembles lib/providers/music_provider.dart from tool/queue_store_chunks/gz_part_*.b64
# (concatenated base64 of gzip-compressed source).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/lib/providers/music_provider.dart"
DIR="$ROOT/tool/queue_store_chunks"
if [[ ! -d "$DIR" ]]; then
  echo "Missing $DIR" >&2
  exit 1
fi
TMP_B64="$(mktemp)"
TMP_GZ="$(mktemp)"
trap 'rm -f "$TMP_B64" "$TMP_GZ"' EXIT
: > "$TMP_B64"
for f in $(ls "$DIR"/gz_part_*.b64 | sort); do
  tr -d '\n' < "$f" >> "$TMP_B64"
done
base64 -d < "$TMP_B64" > "$TMP_GZ"
gzip -dc "$TMP_GZ" > "$OUT"
echo "Assembled $OUT ($(wc -c < "$OUT") bytes)"
grep -q "class MusicProvider" "$OUT"
grep -q "QueueStore" "$OUT"
grep -q "queue_store.dart" "$OUT"
echo "Sanity checks passed"
