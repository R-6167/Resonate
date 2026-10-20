# MusicProvider structural splits

Goal: shrink `lib/providers/music_provider.dart` while keeping the Phase 0 public contract:

`playSong` / `playQueueIndex` / `nextSong` / `previousSong` /
`enqueueSongs` / `playNext` / `removeFromQueue` / `reorderQueue` /
`togglePlayPause` / `pause` / `seek` / `stop`.

## Done (data + runtime state bags)

| Collaborator | Path | Owns |
|--------------|------|------|
| QueueStore | `lib/playback/queue_store.dart` | Queue list, index, shuffle, ID persistence |
| CrossfadeSettings | `lib/playback/crossfade_settings.dart` | Enabled / duration / fade curve (value object) |
| ResumePositionStore | `lib/playback/resume_position_store.dart` | Per-song + last-session resume map |
| AudioFocusSettings | `lib/playback/audio_focus_settings.dart` | Automation enabled + level prefs |
| CrossfadeRuntime | `lib/playback/crossfade_runtime.dart` | In-flight flags, generations, preload ids |
| TransportEpoch | `lib/playback/transport_epoch.dart` | User transport epoch, in-flight/pending, wants-playing |

Temporary patch files and one-shot apply workflows used to land these on GitHub have been removed.

## Still on MusicProvider (higher risk)

- Dual audio engines (A/B), EQ, loudness enhancers
- `_performTrueCrossfade` / preload loaders / engine swap
- DJ handoff surface
- History / focus interruption runtime (duck unduck streams)

## Rules for any future split
1. Public API unchanged
2. Generation / epoch ownership: transport always wins
3. Prefer pure data + state bags first; move async engine methods last
