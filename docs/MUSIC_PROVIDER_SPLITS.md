# MusicProvider structural splits

Goal: shrink `lib/providers/music_provider.dart` while keeping the Phase 0 public contract.

## Done

1. QueueStore
2. CrossfadeSettings (value object)
3. ResumePositionStore
4. AudioFocusSettings
5. CrossfadeRuntime (in-flight flags + generations)

## In progress

### 6. TransportEpoch (`lib/playback/transport_epoch.dart`)
- User transport epoch, in-flight / pending counts, `userWantsPlaying`, `loadingSource`
- Complements CrossfadeRuntime: transport always wins via epoch preemption
- **Not moved:** next/prev/play implementations, serializePlayback body

## Planned

### 7. EnginePair ownership (A/B players, EQ, loudness)
### 8. DJ handoff surface

## Rules
1. Public API unchanged
2. Prefer state bags first; move async methods later
3. Small patches + CI apply when shipping GitHub-only
