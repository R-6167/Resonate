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


## UX refinement — Phase 2 mode identity completion (2026-10-21)

- [x] Complete the nine-mode lightweight artwork system without raster images or added dependencies.
- [x] Use shared artwork on the Modes screen and populated mode shelves; the Now Playing badge shares the same palette and icon language.
- [x] Extend mode-shelf identity to Normal and empty-shelf states so context remains clear when no virtual shelf tracks are present.
- [x] Add widget tests for all mode banner variants, semantic labels, and narrow-screen/large-text rendering.
- [x] PR #129 merged: release APK size is now gated at 100 MiB in CI.
- [x] PR #130 merged: artwork accessibility/layout regression tests; post-merge CI run #39598409138 passed.
- [ ] Device smoke check: switch all modes, inspect empty/populated shelves, verify player badge and large-text/narrow layouts.
- [x] Integrate the nine supplied mode JPEGs from `assets/` into the shared mode artwork banner using explicit enum-to-file mapping, `BoxFit.cover`, contrast gradients, and a graceful lightweight fallback (PR in review).
- [x] Register all nine JPEGs as local Flutter assets; no network loading or dependencies added.
- [x] Add regression coverage for the nine image mappings and narrow/large-text layout.
- [ ] Confirm CI and the measured release APK remains below 100 MiB; manually review actual crops/contrast on device.
- [ ] If the image subject is clipped on a particular device ratio, tune that mode's alignment based on visual review.

Next: Phase 3 — audit Audio Automation, audio-focus behavior, DVC, EQ headroom, loudness leveling, limiter/crossover, and DJ/crossfade controls for clear wording, a canonical home, persistence, and accurate wiring. Keep playback-engine changes isolated from UI simplification.


## UX refinement — Phase 3 audio-control audit update (2026-10-21)

- [x] PR #132 merged: Resonate sound profiles now use the existing EQ category/preset picker; no curve or DSP behavior changed.
- [x] Confirmed Audio Automation is linked from Settings and groups audio focus, pause/resume fade, DVC, named limiter/crossover profiles, EQ headroom, and preamp access.
- [x] Confirmed EQ headroom uses the maximum positive software EQ band to estimate preamp attenuation and routes it through live DSP; this remains a conservative estimate, not output metering.
- [x] Confirmed Audio leveling UI and service describe sampled RMS rather than LUFS/true peak and only apply conservative attenuation to cached analysis.
- [ ] PR for AudioLevelingSettings regression tests must pass CI before merge.
- [ ] Device validation remains necessary for interruption behavior, no surprise resume when another player takes focus, EQ headroom audibility, and leveling sound quality.


---

## Current-code audit — 2026-10-22 (authoritative status)

Audit target: `Resonate-True-Apk`, merge commit `bad0261c7d36f2c5a52cd74dcff230abe1a31e3e` (PR #142). This section supersedes older “still in progress” notes above when they conflict. Historical entries are retained as history, not as current status.

### Verified in source / repository

- [x] **Playback architecture remains extracted, not replaced.** `MusicProvider` is still the public playback facade; queue, transport, crossfade, DJ handoff, audio-effects lifecycle, leveling runtime, and mode policy responsibilities have dedicated collaborators/part files. See `docs/MUSIC_PROVIDER_SPLITS.md`.
- [x] **Transport/crossfade protections are present in code.** The playback audit documents generation/ownership guards, queue-driven repeat, stale-transition cancellation, and bounded failed-source skipping. This is source evidence, not proof that every OEM/device timing case is solved.
- [x] **Nine listening modes and nine local artwork files are present.** Mode banner/widget tests exist. Manual checks of crops, contrast, shelves, badge, and large-text layouts remain open.
- [x] **Release APK size ceiling is enforced in CI at 100 MiB.** Keep checking the measured release artifact; the earlier 76.2 MB figure is a historical baseline, not the current package size. Installed size has not been established here.
- [x] **Five first-party Resonate profiles coexist with classic and custom presets** in the existing EQ catalog. The separate featured profile-card row was removed; profiles now use the shared category/preset picker, as intended.
- [x] **Audio leveling settings have regression tests** for defaults, target clamping, non-finite rejection, unchanged values, and persistence. Runtime uses cached sampled RMS and bounded attenuation; it is not LUFS or true-peak normalization.
- [x] **PR #142 merged:** EQ and master DSP are forced on; their off switches were removed from the EQ UI; persisted limiter/crossover settings are reapplied during initialization; Audio Automation explanatory copy was shortened.
- [x] **Native DSP paths exist** for separate DVC/volume, preamp, EQ bands, limiter ceilings, and crossover frequency. The C++ engine contains a two-band crossover/limiter chain; limiter activity is peak-dependent, and crossover is protection processing rather than a tonal crossover.

### Not yet proven / incomplete

- [ ] **EQ preset regression — priority 1.** The catalog and application/persistence paths exist, but the reported “stuck on one preset” behavior is not considered fixed by source inspection alone. Add focused tests for all five Resonate curves, catalog uniqueness, applying a different preset, selected-state updates, band values, and restart/legacy/custom JSON compatibility. Then verify on device.
- [ ] **DVC / limiter / crossover audible effect.** Bridge methods, registry updates, sticky state, and native processing code exist, but this does not prove the running sink receives the right value or that the user can hear the expected change. Add acknowledgement/state regression tests where possible and run controlled device checks. Limiter changes may only be audible on peaks; crossover should not be judged as a tone control.
- [ ] **Always-on DSP lifecycle.** PR #142 forces the processing flags on, but verify the merged CI result and add/retain regression coverage for new A/B sink registration, session attach/reconnect, and legacy callers attempting to disable processing. A failed native attach must be visible in diagnostics and must not be described as successful processing.
- [ ] **Audio leveling sound quality and persistence on real tracks/routes.** Settings and runtime tests exist; listening validation across quiet/loud material, Bluetooth/headphones, and speaker output remains outstanding.
- [ ] **Audio focus / pause-resume fade.** Controls and persistence are present. Verify notification duck/restore, calls, other-player focus loss, no unwanted auto-resume, and fades on device. Android focus loss does not reliably identify “call” versus “another player”; do not promise call-only behavior.
- [ ] **Engine A default (historical Phase 2 in the playback roadmap).** The roadmap defines the intended policy but does not record a completed call-site audit or focused integration test proving ordinary playback stays on the primary engine and Engine B is used only for a permitted transition/preload. Audit against current engine ownership before checking this off.
- [ ] **Playback/crossfade lifecycle edge cases.** The October 15 playback audit is useful but has stale branch/status wording. Re-run its manual list against the current branch: repeat-one, repeat-all, mode switches, failed source, rapid next/previous during fades, seek during fade, screen-off, and route change. Add focused tests for any reproduced regression.
- [ ] **Mode artwork and visual performance.** Tests cover rendering/accessibility cases, but manual device validation remains. Recheck For You scrolling, expensive blur/glass surfaces, library current-row retention, and navigation/player-state continuity before closing the visual phase.
- [ ] **Current release verification.** The PR #142 post-merge CI run `39738317312` was still in progress when this audit was written. Do not mark the base green until that run concludes successfully. Confirm the 100 MiB gate on the actual successful artifact; installed size is a separate measurement.

### Phase order from this audit (no new features)

1. **Phase A — EQ correctness:** reproduce and fix preset selection/application/persistence; add curve/catalog and migration tests. Preserve the shared picker and custom preset formats.
2. **Phase B — live audio chain correctness:** verify always-on processing/session attach and prove DVC, preamp, leveling, limiter, and crossover values reach current and newly registered A/B engines. Keep controls and DSP behavior separate from UI redesign.
3. **Phase C — audio automation reliability:** focused tests and device checks for duck/restore, focus-loss policy, pause/resume fade, and persisted settings; keep copy concise and truthful.
4. **Phase D — playback ownership regression:** complete the Engine A/Engine B call-site audit and focused transport/crossfade/repeat/mode-boundary tests; fix only reproduced failures.
5. **Phase E — UX/performance closeout:** verify existing mode artwork, EQ identity, navigation, library position, accessibility, and scrolling on device; tune only regressions or existing rough edges.
6. **Phase F — release gate:** green Flutter/native/Android CI, APK below 100 MiB, then a recorded device smoke pass. CI success and subjective listening results must remain separate.

### Phase A/B execution update — 2026-10-22

- [x] PR #144 merged with green CI (run #39743601042): exact EQ preset resolution, stale automatic-selection guards, custom-name uniqueness, legacy 10-band curve migration, and focused catalog/curve tests.
- [ ] **Phase A device verification remains open.** No post-merge device result has been reported yet for Signature → Warmth → Clarity, band edits, profile switching, and persistence after force-stop/restart. Source/CI evidence does not replace this check.
- [x] Phase B source audit confirms the registry retains DVC gain, EQ curve, speaker policy, preamp, limiter ceilings, and crossover as sticky state; new engines are configured before registration and live updates are serialized with registration.
- [ ] Phase B PR adds explicit diagnostic fields for the last-requested preamp, limiter ceilings, and crossover frequency, plus JVM regression coverage. These fields describe registry state inherited by new engines, not measured audio output or proof of audibility.
- [ ] Device validation still needs to confirm DVC/preamp changes on the active route and across an A/B transition; limiter profile differences on peak-heavy audio; crossover settings surviving a newly created engine; and EQ/headroom plus leveling behavior.
- [ ] Do not close Phase B until CI and device checks are separately recorded.

### Phase C regression coverage — 2026-10-22

- [x] PR #145 merged; merge-triggered CI run #39747202298 completed successfully (Flutter analyze/tests, native DSP stress test, Android DSP tests, release APK build, and APK size budget).
- [ ] Phase B listening checks remain open for DVC/preamp, EQ/headroom, leveling, limiter, crossover, and A/B transitions.
- [ ] Phase C test slice adds regression coverage for focus-level clamping, auto-resume gating, persisted fade independence, resume-generation invalidation, the three-minute focus-loss boundary, and duck/deferred-unduck state transitions.
- [ ] Device checks remain required for notification/navigation duck and restore, calls and other-player focus loss, no unwanted auto-resume, and pause/resume fades.


### Audit discipline

A checked source item means the implementation exists; a passing unit test means the tested contract is covered; a green CI run means the configured automation passed; a device/listening check means the behavior was actually exercised on hardware. Do not substitute one category for another. No new features, generic preset-card UI, or broad sound retuning are authorized by this audit. Preserve the existing Resonate sound identity and the 100 MiB package ceiling.

### Phase D regression coverage — 2026-10-22

- [x] PR #146 merged: Phase C focus automation state tests are in the base.
- [x] PR #147 merged: crossfade fallback queue-target boundaries cover a single-item queue under repeat-all vs. repeat-off, and stale transition commits are rejected when current-song identity is absent.
- [x] Source audit completed for repeat-one completion, rapid transport commands during fades, seek cancellation, failed-source recovery, and mode/engine ownership boundaries. Existing guards and bounded recovery are retained; no reproducible defect justified changing runtime playback sequencing in this audit.
- [x] PR #148 merged; CI run #39752681218 passed. The stale completion callback predicate now has isolated unit coverage for current-song completion, outgoing-song completion after ownership moves, active transitions, and missing identity.
- [x] Source review confirms repeat-one has separate self-handoff and seek-to-zero fallback paths; transition generations guard stale handoff cleanup; user transport commands are marked synchronously and receive transport priority; failed queue entries are skipped with a bounded, ID-based scan and Repeat All is the only mode that wraps.
- [ ] Device smoke remains required: repeat-one preserves song/UI identity; repeat-all wraps once; rapid next/previous during crossfade lands on the requested track; seek cancels stale fade commits; failed media source advances to a playable item; mode switches, screen-off, and route changes do not strand playback. This is a hardware validation gate, not a code-only checkbox.
- [x] PR #146 CI run #39747965004 and PR #147 CI run #39750629145 completed successfully. Phase B/C hardware checks remain separate.

### Phase D — implementation closeout

- [x] PR #147 boundary tests and PR #148 completion-ownership tests merged with green CI.
- [x] Audited the relevant live paths without broad runtime rewrites or sound changes; the next code change should be driven by a reproducible device failure.
- [ ] Final device smoke is still outstanding. Do not claim the whole phase is hardware-verified until the checklist above is exercised on the target Android device.

### Phase E — player-only full-screen mode artwork (2026-10-22)

Implementation PR in progress; CI and device review are still pending.

- [x] Reserve the nine supplied mode JPEGs for the Now Playing screen; mode pickers and shelves use lightweight drawn identity instead of the photographs.
- [x] Add a full-screen, mode-mapped player backdrop with cover fit, restrained readability gradients, low-quality resized image decoding, and a gradient fallback if an asset fails.
- [x] Preserve the live audio visualizer, mode badge, swipe gestures, transport controls, and existing playback behavior over the background.
- [x] Add widget tests for all nine image mappings, semantic labels, and the absence of supplied photographs in mode-picker banners.
- [ ] Confirm CI is green, including the existing 100 MiB release APK gate.
- [ ] On device, inspect all nine crops, control readability, mode-switch transitions, narrow/large-text layouts, and scrolling performance. These checks remain separate from automated tests.
- [ ] Measure the release APK from the same workflow/build variant and record it; keep the existing 100 MiB ceiling.

Scope guard: this phase changes presentation only. Do not retune Resonate Signature, Warmth, Clarity, Afterhours, or Pulse, add a second preset picker, or change playback ownership unless a reproducible defect is found.
