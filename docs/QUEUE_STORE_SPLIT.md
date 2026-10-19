# First split: QueueStore

Branch target: `Resonate-True-Apk`

## What changed

1. **New** `lib/playback/queue_store.dart`  
   Owns queue list + index, shuffle flag, id persistence, and mutators.

2. **Updated** `lib/providers/music_provider.dart` (via patch)  
   Wires `QueueStore` with compatibility aliases. Public API unchanged.

## Apply

```bash
bash scripts/apply_queue_store_split.sh
dart analyze lib/playback/queue_store.dart lib/providers/music_provider.dart
flutter test
```

## Next splits

1. VolumeMaster
2. HistoryRecorder
3. CrossfadeController
