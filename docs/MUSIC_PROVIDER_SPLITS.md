# MusicProvider structural splits

Goal: shrink `lib/providers/music_provider.dart` by extracting pure data and
bounded collaborators while keeping the Phase 0 public contract.

## Done

### 1. QueueStore
### 2. CrossfadeSettings (value object file; prefs may still live with CrossfadeProvider)
### 3. ResumePositionStore
### 4. AudioFocusSettings

## In progress

### 5. CrossfadeRuntime (`lib/playback/crossfade_runtime.dart`)
- In-flight flags, automatic + repeat-self generations, preload ids
- `clearFlags`, `isLive`, `hasAutomaticWork`
- **Not moved:** `_performTrueCrossfade`, preload loaders, engine swap
- User settings (`_crossfadeEnabled` / duration / fade) and `_userTransportEpoch` stay on MusicProvider

## Planned

### 6. TransportEpoch / command gate
### 7. EnginePair ownership
### 8. DJ handoff surface

## Rules
1. Public API unchanged
2. Generation ownership stays with transport authority (`_userTransportEpoch` on provider)
3. Prefer state bags first; move async engine methods only after flags are isolated
