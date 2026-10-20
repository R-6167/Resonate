# MusicProvider structural splits

`MusicProvider` remains the public playback facade. Async ownership has been split into same-library `part` files so existing private state/API can remain stable while each area is reviewed independently.

## Done (collaborators under `lib/playback/`)

| Collaborator | Owns |
|--------------|------|
| QueueStore | Queue list, index, shuffle, ID persistence |
| CrossfadeSettings | Enabled / duration / fade (value object; may still dual-own with CrossfadeProvider) |
| ResumePositionStore | Per-song + last-session resume |
| AudioFocusSettings | Automation enabled + level prefs |
| CrossfadeRuntime | In-flight flags, generations, preload ids |
| TransportEpoch | User epoch, in-flight/pending, wants-playing |
| EnginePair | A/B players + Android EQ/loudness construction |
| DjHandoffState | DJ feature flags + last-handoff snapshot |
| AudioLevelingSettings | Leveling enabled + target RMS prefs |

## Completed orchestration extractions (2026-10-20)

| Part file | Responsibility | Integration boundary |
|---|---|---|
| `music_provider_crossfade.dart` | Crossfade preload, transition, and fallback orchestration | Uses `CrossfadeRuntime`, `TransportEpoch`, and the provider-owned A/B engines; user transport must still preempt automatic work |
| `music_provider_transport.dart` | Play/pause/next/previous/seek command orchestration | Public `MusicProvider` API remains the stable entry point; serialized transport and intent gates remain authoritative |
| `music_provider_dj_handoff.dart` | DJ transition planning, execution, and recovery | Optional intelligence layer; must retain safe fallback and never claim engine ownership |
| `music_provider_audio_effects_lifecycle.dart` | Deferred effect activation and saved-effect sync | Uses `AudioEffectsController`; activation stays off the source-load/play critical path |

These are Dart `part` files, not standalone services: their `part of 'music_provider.dart';` declarations and matching `part` directives in the provider are the intended connection. CI passing confirms compilation/tests, but runtime device checks are still needed for route changes, screen-off playback, and dual-engine handoff.

## Still on MusicProvider — recommended extraction order

### Low risk (state / prefs bags)
1. **FocusInterruptionRuntime** — `_isDucked`, unduck-pending, focus-resume generation, loss timers
2. **PlaybackHistorySession** — active `ListeningEvent`, serial queue, position ticks
3. **GaplessWindowState** — concatenating window ids / start index / active flag
4. **ModePlaybackPolicy** — `_modeCrossfadeAllowed`, shuffle allowed, precise resume, mode boundary gen
5. Finish **CrossfadeSettings** wiring into `setCrossfade*` if UI prefs still live only on CrossfadeProvider

### Medium risk (coordinators, still thin)
6. **LevelingRuntime** — `_eqPreampScale`, `_trackLevelingScale`, generation, refresh orchestration (keep LoudnessService)
7. **VolumeFacade** — user volume, sleep fade, system volume poll channel
8. **PlayerStreamBinder** — `_bindActivePlayerStreams`, position/state/duration subscriptions

### High risk (async orchestration — do last)
9–12. The four async orchestration areas above have been extracted; avoid another broad move until focused integration tests cover the ownership boundaries.

## Rules
1. Public API unchanged
2. Transport always wins (TransportEpoch preempts CrossfadeRuntime)
3. State bags first; move async engine methods only after flags are isolated
4. Prefer small wire patches + CI when shipping GitHub-only
