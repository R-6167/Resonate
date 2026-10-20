# MusicProvider structural splits

Goal: shrink `lib/providers/music_provider.dart` by extracting pure data and
bounded collaborators while keeping the Phase 0 public contract:

`playSong` / `playQueueIndex` / `nextSong` / `previousSong` /
`enqueueSongs` / `playNext` / `removeFromQueue` / `reorderQueue` /
`togglePlayPause` / `pause` / `seek` / `stop`.

## Done

### 1. QueueStore (`lib/playback/queue_store.dart`)
- Owns: songs list, index, shuffle flag, ID persistence keys
- MusicProvider keeps thin `_queue` / `_queueIndex` / `_shuffleEnabled` aliases
- Status: merged to `Resonate-True-Apk`; **integration still hybrid** — some
  paths still duplicate persist logic with local key constants. Follow-up should
  route `_persistQueue` / `_restoreQueue` / `setShuffleEnabled` through
  `QueueStore.persist` / `loadPersistedIds` / `shuffleUpcoming`.

## In progress / next

### 2. CrossfadeSettings (`lib/playback/crossfade_settings.dart`)
- Owns: enabled, durationMs, fadeType (+ optional prefs keys)
- Does **not** own runtime transition flags or A/B engine work
- `setCrossfadeEnabled(false)` invalidation stays on MusicProvider
- Note: comments already say CrossfadeProvider restores UI prefs; this type is
  the shared value object so both sides stop forking clamp/allowed-type logic

### 3. ResumePositionStore (planned)
- `_resumeBySongId` map + load/save of `playback_resume_map_v1`
- Current + last song resume fields can stay on MusicProvider initially

### 4. AudioFocusSettings (planned)
- automation enabled + level + prefs keys
- duck/unduck runtime stays on MusicProvider until a later FocusController

### 5. Later (higher risk)
- CrossfadeRuntime (in-flight flags, generations, preload)
- TransportEpoch / command gate
- EnginePair ownership
- DJ handoff surface

## Rules for each split
1. Public API unchanged
2. Generation / epoch ownership stays with transport authority
3. Prefer pure data + persist first; runtime engines last
4. Prefer small patches over full-file rewrites when shipping via GitHub only
