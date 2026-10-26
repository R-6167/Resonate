# Media3 provider cutover audit

This audit records the remaining production ownership boundary before Media3 can replace the legacy engine. It is intentionally based on the current `media3-playback-observation-contract` branch and is a migration gate, not a claim that cutover is complete.

## Current ownership

- `MusicProvider` constructs an `EnginePair` containing two `just_audio` players. `audioPlayer` resolves to the currently active legacy player.
- `JustAudioPlaybackObservationSource(() => audioPlayer)` observes that same active player. This is deliberately consistent: commands and UI observations still share legacy ownership.
- `Media3ProviderSession` now has a single-flight startup contract and a provider-facing state projection, but `MusicProvider` does not yet own/use it in production.
- Do not replace the observation source alone. That would expose Media3 state while legacy players continue to issue commands and produce sound.

## Production dependencies that must move together

| Responsibility | Current implementation surface | Cutover requirement |
| --- | --- | --- |
| Queue and identity | `MusicProvider` queue store and song selection; Media3 adapter maps `Song` queue entries | Preserve occurrence identity, current index, queue edits, repeat-one/all, shuffle, and invalid-index behavior |
| Transport | `music_provider_transport.dart` plus direct active-player operations in `music_provider.dart` | Route play, pause, stop, seek, next, previous, restart, and completion through one session |
| Crossfade / preload | `music_provider_crossfade.dart`, `music_provider_dj_handoff.dart`, and legacy player A/B operations | Use native two-deck transition; preserve cancellation, interruption, standby invalidation, DJ handoff, and consecutive fades |
| State / progress | `JustAudioPlaybackObservationSource`, active-player stream binding, provider state fields | Media3 snapshots must own playing, position, duration, readiness, and current-track identity without stale snapshot rollback |
| Volume / DSP | `VolumeFacade`, `LevelingRuntime`, audio effects controller, equalizer/loudness enhancer and Android audio-session IDs | Compose master volume, track trim, preamp, sleep fade, focus ducking, and transition envelopes without competing gain writes |
| Platform controls | `AudioServiceHandler` callbacks, audio-session subscriptions, audio focus/session setup | Notification, lock-screen, Bluetooth/headset and focus commands must reach the same authoritative session |
| Persistence / history | Resume-position store, playback-history session, database writes and track-change listeners | Keep resume position, listening history, play count and force-stop recovery consistent with native events |
| Modes / intelligence | Podcast and audiobook bridges, mode playback policy, DJ/autopilot and intent gate | Preserve mode-specific restrictions and intent/cancellation ownership; no parallel legacy playback |
| Resource lifecycle | Provider dispose, player subscriptions, native session and Media3 runtime/bridge | No leaked listeners, duplicate native subscriptions, late state publication or commands after disposal |

## Sequencing decision

Do not perform a broad text replacement of `audioPlayer` or inject Media3 only into public transport methods. The provider still contains direct legacy engine operations in queue loading, active-player recovery, gain restoration, repeat/completion handling, crossfade, and DJ handoff. A partial switch would create two playback authorities.

The first production integration change should establish one provider-owned session boundary and route a coherent command-and-observation slice through it. Before switching the default, the complete queue/transport/crossfade/state path must have parity tests. Gain/effects, platform controls, persistence/history, and modes then need to be migrated against that same owner before the legacy pair can be removed.

## Verification gate

Before any production-default cutover:

- [ ] Unit tests prove one command authority and one state authority.
- [ ] Queue occurrence identity survives duplicate songs, edits, next/previous, repeat, and shuffle.
- [ ] Play/pause/seek/stop and completion cannot desynchronize provider state from audible output.
- [ ] Consecutive native crossfades, cancellation, pause/resume, queue replacement, and DJ handoff pass regression tests.
- [ ] Gain factors compose with transition envelopes; no full-volume restoration or audible dip regressions.
- [ ] Audio focus, Android audio-session effects, notification/Bluetooth controls and background playback pass.
- [ ] Resume position, listening history, modes and force-stop recovery remain correct.
- [ ] Flutter analysis/tests and Android debug build are green; device validation includes Android 7 and a newer Android device.

Until these gates pass, `just_audio` remains the production engine. This audit does not authorize a cutover or remove legacy dependencies.
