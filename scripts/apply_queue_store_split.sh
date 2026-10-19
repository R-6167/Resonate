#!/usr/bin/env bash
# Applies the QueueStore extract to lib/providers/music_provider.dart
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
patch -p1 < patches/music_provider_queue_store.patch
echo "Applied music_provider_queue_store.patch"
echo "Ensure lib/playback/queue_store.dart is present, then run: dart analyze lib/playback lib/providers/music_provider.dart"
