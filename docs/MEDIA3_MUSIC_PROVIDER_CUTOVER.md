# Media3 MusicProvider Production Cutover

## Current boundary

Media3 is not yet the production playback owner. `MusicProvider` still constructs `EnginePair`, routes transport through two `just_audio` players, binds its public playback streams to `JustAudioPlaybackObservationSource`, and applies Android DSP effects to the two legacy audio sessions.

`Media3ProviderSession` already composes the Media3 runtime and state bridge behind `PlaybackEngineSession`. Its commands and observations share one reconciled state owner. That session is currently not injected into production `MusicProvider`.

Do not switch only observations or only commands. Either change would create split authority between the UI/provider and the actual audio engine.

## Required production ownership contract

Before the production provider selects Media3, one session must own all of the following:

- Queue load, queue edits, selected occurrence, persistence/restore reconciliation.
- Play, pause, stop, seek, next, previous, repeat, shuffle, and playback speed.
- Position, buffered position, duration, playing, buffering, completion, readiness, and error observations.
- Audio focus/interruption/noisy-route behavior and the active Android audio-session ID.
- Gain staging, track leveling, sleep fade, focus ducking, DSP attachment and detach/rebind.
- Automatic crossfade, manual handoff, preload invalidation, DJ tempo/stretch and transition cancellation.
- Audio-service/notification transport commands and published media/queue state.
- Playback history, mode boundaries, watchdog/recovery and disposal.

The session is the sole command and observation authority. Provider fields may remain as UI-facing projections, but must not independently infer or issue engine state changes.

## Migration sequence

### 1. Close the Media3 session contract

- Keep command serialization and snapshot reconciliation inside the session/runtime.
- Add explicit backend capabilities for every production behavior that cannot safely be represented by the current generic transport API.
- Add contract tests for command ordering, stale snapshot rejection, queue edits, duplicate track occurrences, errors, lifecycle, and audio-session handoff.
- Do not silently fall back to a legacy player when a Media3 operation is unsupported.

### 2. Port transition and effects ownership

- Replace the implicit `EnginePair` dependency in crossfade/DJ code with an explicit Media3 transition/deck contract.
- Preserve independent outgoing/incoming gain and tempo control where required; a single global speed or volume setter is not equivalent.
- Make DSP attach/detach follow the active native audio-session ID, including deck promotion and session loss.
- Verify cancel, preemption, repeat-self handoff, and queue mutation invalidate stale preloads.

### 3. Cut over MusicProvider as one vertical slice

- Inject one `PlaybackEngineSession` at the provider composition boundary.
- Route queue and transport commands through that session.
- Bind provider/UI observations and synchronous getters to the same session state.
- Move notification callbacks and published media state to that authority.
- Keep history, modes, focus, recovery and persistence behavior intact.
- Gate production selection until all required capabilities are present; no dual-engine playback fallback.

### 4. Remove the legacy engine

- Delete `EnginePair`, legacy stream binding and legacy player references from provider/transport/crossfade/DJ/effects code.
- Remove `just_audio` imports and dependency only after repository-wide references and tests prove they are no longer required.
- Run analyzer, unit/widget/integration tests, Android debug and release builds.
- Physically validate playback, queue edits, seek, next/previous, notification/lockscreen, background, interruptions, Bluetooth, crossfade, DJ handoff, DSP, restore and low-memory behavior before merging to the production branch.

## Current blockers confirmed by source audit

- `MusicProvider` constructor creates the legacy `EnginePair` and binds legacy observations.
- `music_provider_transport.dart` uses active/inactive legacy players for pause and handoff behavior.
- `music_provider_crossfade.dart` and `music_provider_dj_handoff.dart` require explicit outgoing/incoming player objects and per-deck controls.
- `EnginePair` owns two players and two sets of Android Equalizer/LoudnessEnhancer instances.
- The current generic `PlaybackEngineSession` exposes queue/transport/crossfade operations, but does not yet express the complete per-deck DJ/effects contract.

## Merge gate

Keep the production cutover PR open and unmerged until the complete ownership contract is implemented, CI is green on the final head, Android builds succeed, and the production-wired build has passed physical device testing. A green preparatory test suite is not evidence that production has switched engines.
