# Resonate Remake — Playback Core Roadmap

Branch: `Resonate_Remake` (from `Companion_Features_Diagnostics`)  
Also tracked on `Resonate-True-Apk` / `cleanup-docs-audit`

## Goal
Musicolet-like reliability for normal play, with Intelligence as an optional layer (not removed).

## Engine policy
- **Engine A** — primary player for normal listening
- **Engine B** — crossfade and/or Autopilot-prepared next (only with consent)

## Phases

### Phase 0 — Contract
Public APIs only: `playSong`, `playQueueIndex`, `nextSong`, `previousSong`, transport, enqueue. Intelligence must not set engines/tokens/`isPlaying` directly.

### Phase 1 — Flexible queue
- [x] `playQueueIndex(i)`
- [x] Queue UI: every row tappable
- [x] `removeFromQueue` for non-current indices
- [x] `playSong` cancels automatic work so library tap wins

### Phase 3 — Single completion path
- [x] `onTrackEnded` + fresh intent token
- [x] End-of-track watchdog
- [x] Advance via internal next play

### Phase 4 — Transport always wins
- [x] `_cancelAutomaticPlaybackWork()` shared by play / toggle / pause / stop / next / prev / seek
- [x] Clears crossfade, auto-advance, watchdog
- [x] Play / toggle retries `play()` if native player did not start
- [x] Media-session and Intelligence next stay instant (no forced crossfade)

### Phase 2 — Engine A default
**Target behaviour**
- Non-crossfade path stays on Engine A only.
- Engine B is allocated only for active crossfade transitions or consented Autopilot preload.
- After a crossfade completes, ownership returns cleanly to Engine A (or the surviving engine becomes the new A).
- No background code path may silently switch the primary engine.

**Implementation notes**
- Audit every call site that creates or switches engines.
- Ensure `MusicProvider` / playback coordinator treats Engine A as the default for `playSong`, `playQueueIndex`, seek, and media-session commands.
- Crossfade and Autopilot explicitly request Engine B and release it when finished.

### Phase 5 — Intelligence optional
- [x] Off / no consent blocks Intelligence play / queue / next mutations.
- [x] Graduated + consent may enqueue / playNext / optional B preload only via public APIs.
- [x] Intelligence does not own engine ownership, intent tokens, or `isPlaying` flags.
- [x] Autopilot checks the three gates together: explicit consent, Intelligence enabled, and Autopilot selected.
- [x] Re-check the gate after asynchronous decision boundaries before each subsequent mutation.
- [x] Synchronous consent gate avoids an extra scheduling gap before a playback mutation.
- [x] Diagnostics record blocked mutation attempts.
- [x] Policy tests cover each independent gate; exhaustive truth-table coverage added in PR #57.

### Phase 6 — Cleanup + smoke checklist
- [x] Remove committed `android/.gradle/` cache files (PR #56).
- [x] Extract Android effects channel handling (PR #58), PCM analysis (PR #59), and folder scanning (PR #60).
- [x] Isolate live DSP channel argument/response translation from system audio effects (PR #61); `MainActivity` retains activity-result/permission lifecycle work.
- [x] Device smoke on target Android hardware: normal playback, seeking, next/previous, force-stop and restore, Bluetooth connect/disconnect and route changes, crossfade on/off, and Intelligence on/off (user-reported pass, 2026-10-19).
- [x] Check logs for engine thrashing with Intelligence disabled (user-reported pass, 2026-10-19).

## Verification status
- PR #55 synchronous consent gate is merged; its full CI run passed.
- PR #56 removed tracked Gradle cache files; post-merge CI run #39233913866 passed.
- PR #58 effects-channel extraction and PR #59 PCM extraction were merged with passing CI; PR #60 folder-scan extraction is merged after green CI run #39240960122.
- PR #61 live DSP channel translation is isolated from Android system effects without changing channel names, arguments, defaults, response maps, or registry ownership. PR #61 CI passed before merge.
- Post-merge CI for PR #61 passed: run #39243034607 on `Resonate-True-Apk`, merge commit `b997f74fecf1f8090e9e33577967a0677f528cdf`.
- Phase 6 device smoke checklist and the Intelligence-disabled engine-thrashing log check were reported as passing on target Android hardware on 2026-10-19. These are user-reported device results, separate from CI verification.

## Historical local cleanup instructions
The repository previously contained committed Gradle caches. PR #56 removes the tracked files; the existing `.gitignore` should keep local cache files out of future commits.

## Hardening and usability pass — 2026-10-21

Status: PR #120 and PR #121 are merged to `Resonate-True-Apk`. PR #121 merge commit: `06b6ad9f3b706a6121b0c2e4b2ee087bdcb15d8f`. Device smoke tests for its audio-reactive/DSP UX changes remain to be confirmed separately; a merged PR is not evidence that subjective sound or on-device behavior has been validated.

- [x] Move Library search into the top navigation icon and reclaim the always-visible search-field space.
- [x] Restore the current track's row position when the track is visible in the current library result set; retain the user's scroll position while the current track is unchanged.
- [x] Remove the duplicate DJ Mode entry in Settings; keep the canonical entry under Playback.
- [x] Guard CrossfadeProvider against a late initial SharedPreferences read overwriting a user's immediate setting change.
- [x] Refresh About & How to use copy for current search, crossfade/mode policy, automation, audio-reactive visualization, and explicit Autopilot consent.
- [x] Replace the root MIT terms with a Resonate Restricted Use License for original Resonate materials; third-party components remain governed by their own licenses.
- [x] Remove the duplicate inner Ask Resonate panel, persist its selected shape, move shape choices to Visualization & Orb, and rebuild the boundary on live spectrum updates.
- [x] Increase low-level spectrum response visibility for the orb and main visualizer; clear stale spectrum values when capture stops or is unavailable.
- [x] Restore saved DVC to the native DSP registry at audio-effects startup so new A/B engines inherit it.
- [x] Add a persisted Pause/resume fade toggle and wire it to manual transport pause/resume.
- [x] Replace limiter/crossover micro-adjustment sliders with named peak-protection profiles and clarify that they are not tone controls.
- [x] Replace the Crossfade DJ settings banner with a compact chip; use the logo mark alone on Home and a larger background logo on About.
- [x] Add a regression test for pause/resume fade preference persistence.
- [ ] Audit playback/crossfade state transitions and add focused regression tests where practical.
- [ ] Verify overlay shape/audio response, DVC audibility and persistence, pause/resume fades, limiter profiles, branding, and optional spectrum fallback on target Android hardware.

## UX refinement program — 2026-10-21
The new `docs/RESONATE_UX_REFINEMENT_PLAN.md` defines the phased UX and sound-identity work, with mode artwork and a 100 MB app-size ceiling. It begins with an audit and measurable baseline; it does not authorize feature changes before the current behavior, release size, and test requirements are understood.


## UX refinement — Phase 0 audit — 2026-10-21

- [x] PR #122 merged; its CI passed. Post-merge CI run #39584802997 was still running at the time the audit was recorded and must be checked separately.
- [x] Added `docs/RESONATE_UX_PHASE_0_AUDIT.md` with the current screen/mode/EQ/DSP/art inventory and Phase 1 acceptance notes.
- [x] Current listening-mode enum has nine entries (Normal, Running, Workout, Driving, Work, Podcast, Motivation, Audiobook, Sleep); `docs/MODES.md` previously omitted Workout and Sleep; this PR corrects that documentation mismatch.
- [x] EQ currently has 32 built-in generic category-based presets plus custom save/delete and versioned JSON import/export. Phase 1 must preserve custom preset compatibility and evaluate headroom before adopting curves.
- [x] CI release APK baseline: 76.2 MB from run #39579384222, using `flutter build apk --release --no-shrink`. This is below the current 100 MB APK ceiling by about 23.8 MB on the same reported measure. It is not an installed-size measurement.
- [x] Existing asset tree has branding PNGs and SFX, but no dedicated mode artwork. The two branding PNGs total 2,727,164 bytes; six SFX total 208,416 bytes; all tracked `assets/` files total about 2.80 MiB.
- [ ] Check post-merge CI run #39584802997 before considering the current base fully green.
- [ ] Add an explicit APK-size threshold to CI only after a fresh base build confirms the measurement and threshold convention.
- [ ] Keep device installed-size measurement separate from APK size; it has not been measured in this audit.

Next recommended phase: Phase 1 — Resonate sound identity and EQ. Define the reference sound and first-party profile intents, verify native DSP/headroom behavior, and add curve/persistence/migration tests before redesigning the EQ UI. No feature implementation was included in Phase 0.


## UX refinement program — Phase 1 sound identity — 2026-10-21

- [x] Phase 0 inventory PR #123 merged; its follow-up post-merge CI was checked separately before implementation.
- [x] Added five conservative first-party EQ profiles to the existing catalog: Resonate Signature, Warmth, Clarity, Afterhours, and Pulse. Existing classic profiles and custom presets remain available.
- [x] Curves use the current 10-band preset contract and modest gain ranges; they are initial design profiles, not yet described as listening-validated.
- [ ] Add profile curve/catalog tests and verify selection/persistence plus legacy/custom JSON compatibility.
- [ ] Confirm the native DSP and automatic-headroom path, then record listening checks across varied recordings and output routes.
- [ ] Keep the release APK below the existing 100 MB ceiling; establish a fresh comparable baseline before adding a CI size-failure gate.


## UX refinement program — EQ profile picker — 2026-10-21

- [x] Added a dedicated first-party Resonate sound-profile card row to the existing EQ screen; profiles are discoverable without navigating the category chips.
- [x] Cards provide short plain-language intent, distinct icons, accessible text labels, and an exact selected-state indicator.
- [x] Preset application uses the existing EqualizerProvider path; no DSP, storage schema, dependency, or playback-engine changes.
- [ ] Confirm PR #124 post-merge release build and APK size; current post-merge CI run #39587954052 is still in progress at the last check.
- [ ] Validate profile selection and persistence on device, then continue the remaining native headroom and listening checks before declaring Phase 1 complete.
