# MusicProvider structural splits

Goal: shrink `lib/providers/music_provider.dart` while keeping the Phase 0 public contract.

## Done

| Collaborator | Path |
|--------------|------|
| QueueStore | `lib/playback/queue_store.dart` |
| CrossfadeSettings | `lib/playback/crossfade_settings.dart` |
| ResumePositionStore | `lib/playback/resume_position_store.dart` |
| AudioFocusSettings | `lib/playback/audio_focus_settings.dart` |
| CrossfadeRuntime | `lib/playback/crossfade_runtime.dart` |
| TransportEpoch | `lib/playback/transport_epoch.dart` |

## In progress

### EnginePair (`lib/playback/engine_pair.dart`)
- Construction of A/B `AudioPlayer` + Android EQ/loudness
- `activeIsA`, active/inactive accessors, `swap` / `resetToA` / `dispose`
- **Still on MusicProvider:** stream binding, session callbacks, crossfade orchestration, `AudioEffectsController`

## Planned

- DJ handoff surface
- Move more of `_performTrueCrossfade` onto collaborators after EnginePair settles

## Rules
1. Public API unchanged
2. Transport always wins (TransportEpoch + CrossfadeRuntime)
3. Prefer ownership of construction first; async orchestration later
