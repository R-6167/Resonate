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
- Persist / shuffle routed through `QueueStore.persist` / `shuffleUpcoming`

### 2. CrossfadeSettings (`lib/playback/crossfade_settings.dart`)
- Owns: enabled, durationMs, fadeType (+ optional prefs keys)
- Does **not** own runtime transition flags or A/B engine work
- Note: CrossfadeProvider may still restore UI prefs; this is the shared value object

## In progress

### 3. ResumePositionStore (`lib/playback/resume_position_store.dart`)
- Owns: per-song map, last-session song/position, prefs keys, throttle
- `MusicProvider._persistResumePosition` becomes compute-position + `record`/`persist`
- Public `resumePositionFor` / `resumePositionMs` / `resumeSongId` preserved

## Planned

### 4. AudioFocusSettings
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
