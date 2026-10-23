# Resonate Media3 Migration Plan

## Decision

Resonate will move toward AndroidX Media3 as its native Android playback foundation. This is an incremental migration, not a big-bang rewrite. The motivation is to give Resonate explicit access to native player, timeline, track, audio-session, and media-session APIs without continually working around abstractions in the current Flutter player layer.

This document records the direction and migration gates. It does not claim that playback has already been migrated.

## Current baseline

- Flutter app currently depends on `just_audio`, `audio_service`, and `audio_session`.
- `MusicProvider` owns two `just_audio` players through `EnginePair`, coordinating preload, crossfade, transport ownership, volume, leveling, and native effects.
- Android already has native Kotlin audio-effect / PCM analysis handlers and a Media3 Common dependency, but not yet a Resonate-owned Media3 ExoPlayer playback service.
- PR #161 added diagnostics around the pre-fade volume state. Preserve this evidence path during migration.
- Playback stability on older Android devices is a release constraint. Android 7 remains an explicit test target.
- The reported ~150 MB RAM figure is a baseline to measure by scenario, not proof of a leak.

## Target architecture

1. **Native playback service owns the players.** A Kotlin service built around Media3 ExoPlayer and MediaSession owns playback lifecycle and both decks. Flutter must not independently create or control a competing authoritative player.
2. **One coordinator owns transitions.** A native coordinator is the only component allowed to perform crossfade gain ramps, preload handoff, cancellation, and active-deck swaps. Every operation carries a generation/token so stale async work cannot alter a newer transition.
3. **Explicit player handles and state.** A typed Flutter platform interface exposes commands and immutable state/events, not raw mutable player objects across the platform boundary. Native code retains direct access to ExoPlayer, Player, Timeline, TrackSelection, AudioAttributes, and session IDs.
4. **One volume policy.** Separate user volume, leveling/preamp, focus ducking, sleep fade, and per-deck crossfade gain. Define their composition centrally; never restore master volume to undo a legitimate focus or user-volume change.
5. **MediaSession is authoritative for system controls.** Notification, lock screen, Bluetooth, headset and external transport actions route into the same service/coordinator as in-app controls.
6. **Effects are explicit and observable.** Inventory which DSP effects run in the native audio path, which depend on Android audio-session IDs, and which are UI-only. Do not advertise a control as working unless changing it affects the live output and has a test.
7. **Flutter remains the product/UI layer.** Keep Resonate modes, library, sound identities, settings, diagnostics and UI in Flutter unless a capability demonstrably needs to move native.

## Migration stages

### Stage 0 — architecture and compatibility inventory
- Map every current playback entry point and all consumers of `AudioPlayer`, `AudioHandler`, audio-session IDs, equalizer/loudness objects, and native effects.
- Document current source of truth for queue/index, current track, position, playing state, repeat, audio focus, crossfade ownership, and mode-specific playback.
- Record supported Android API/device constraints and required codecs/formats.
- Add a feature-to-native-API map and migration risks before replacing dependencies.

**Exit gate:** every playback responsibility has one named owner and a migration destination; current behavior and regression tests are listed.

### Stage 1 — native Media3 vertical slice
- Add compatible Media3 ExoPlayer, Session, and required data-source dependencies, aligned to one tested Media3 version.
- Implement a native service/session and a narrow MethodChannel or Pigeon-style interface for initialize, set source/queue, play, pause, seek, state events, and release.
- Keep the slice isolated behind a playback interface. Do not remove `just_audio` yet.
- Verify foreground playback, notification/lock-screen actions, Bluetooth transport, audio focus, backgrounding, and service recreation on supported Android versions.
- Add JVM/unit tests for command/state mapping and instrumentation/device smoke tests where feasible.

**Exit gate:** the Media3 slice plays local files and survives lifecycle/system-control scenarios without competing with the current engine.

### Stage 2 — dual-deck and crossfade
- Implement two service-owned ExoPlayer instances and preloading before fade time.
- Make all preparation complete before the transition window; no synchronous setup or effects handoff may lower outgoing gain before the fade starts.
- Drive both deck gains from one monotonic transition clock; use explicit cancellation and ownership guards.
- Preserve the outgoing deck's effective gain unless a documented volume/focus policy changes it.
- Emit transition diagnostics: prepare duration, per-deck gain, positions, buffering state, focus/duck state, generation and abort reason.
- Compare with PR #161 diagnostics and test many consecutive transitions with DJ effects both enabled and disabled.

**Exit gate:** no audible pre-fade dip or gap in repeated device tests; manual next/previous/seek/pause during a fade cannot cause stale writes, rewind, volume spikes, or wrong-track UI.

### Stage 3 — effects, leveling and visualization integration
- Map equalizer, loudness enhancement, DVC/leveling, limiter/crossover and session-ID-based effects to the actual Media3 audio output path.
- Expose stable native session IDs for the active deck and ensure effects are attached/re-attached correctly across deck swaps and route changes.
- Audit FFT/PCM visualization separately; the visualizer must not block or stall playback.
- Add tests proving every displayed DSP control changes the native engine and survives save/restore and deck handoff.

**Exit gate:** effect controls are verified end-to-end, including both decks and route changes. Unsupported controls are clearly handled rather than silently no-op.

### Stage 4 — parity and controlled cutover
- Build a behavior parity matrix covering normal play, queue operations, modes, audiobook/podcast session bridges, repeat/shuffle, resume, sleep fade, crossfade, DJ handoff, audio focus, Bluetooth, notifications, library rescans, force-stop restore, and error recovery.
- Run comparative performance tests: idle, normal playback, crossfade, visualization, library scan and DJ analysis. Record peak and retained memory plus CPU and transition latency.
- Test the minimum supported Android API (including Android 7 if still supported by project constraints) and a current Android version.
- Only after parity and device validation, switch the default engine to Media3. Keep the old engine available during development for comparison; remove obsolete dependencies only after no production path uses them.

**Exit gate:** green CI plus device sign-off for the parity matrix, no unresolved playback regressions, and a measured performance comparison.

## Non-negotiable guardrails

- No new product features as part of the engine migration.
- Preserve all ten Resonate-created sound identities and existing Resonate sound character.
- Do not remove the old engine or its dependencies during the initial native vertical slice.
- Do not claim CI or device validation unless it actually ran and passed.
- Treat the user's ~150 MB RAM report as a baseline; compare equivalent scenarios before optimizing.
- Keep each stage in a small reviewable PR with green CI before proceeding.
- Never let Flutter UI state and native Media3 state both act as authoritative playback state.
- Never let DSP, visualization, DJ analysis or library scanning block the playback control path.

## First implementation task

Complete Stage 0: inventory the actual repository call graph and build a responsibility/ownership table before introducing a second playback engine. Then Stage 1 can add Media3 behind an interface without prematurely rewriting `MusicProvider` or destabilizing current playback.
