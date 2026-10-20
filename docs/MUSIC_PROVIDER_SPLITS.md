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

### 2. CrossfadeSettings (`lib/playback/crossfade_settings.dart`)
- Owns: enabled, durationMs, fadeType (+ optional prefs keys)
- Runtime transition flags stay on MusicProvider / CrossfadeProvider

### 3. ResumePositionStore (`lib/playback/resume_position_store.dart`)
- Owns: per-song map, last-session song/position, prefs keys, throttle

### 4. AudioFocusSettings (`lib/playback/audio_focus_settings.dart`)
- Owns: automation enabled + level (1–4) + prefs keys
- Duck/unduck, focus-loss timers, interruption streams stay on MusicProvider

## Planned (higher risk)

### 5. CrossfadeRuntime
- In-flight flags, automatic generations, preload state

### 6. TransportEpoch / command gate
- User transport epoch, pending counts, generation tokens

### 7. EnginePair ownership
- A/B players, equalizers, loudness enhancers

### 8. DJ handoff surface

## Rules for each split
1. Public API unchanged
2. Generation / epoch ownership stays with transport authority
3. Prefer pure data + persist first; runtime engines last
4. Prefer small patches over full-file rewrites when shipping via GitHub only
