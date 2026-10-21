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

Status: implementation branch in progress; do not mark complete until CI and device smoke tests pass.

- [x] Move Library search into the top navigation icon and reclaim the always-visible search-field space.
- [x] Restore the current track's row position when the track is visible in the current library result set; retain the user's scroll position while the current track is unchanged.
- [x] Remove the duplicate DJ Mode entry in Settings; keep the canonical entry under Playback.
- [x] Guard CrossfadeProvider against a late initial SharedPreferences read overwriting a user's immediate setting change.
- [x] Refresh About & How to use copy for current search, crossfade/mode policy, automation, audio-reactive visualization, and explicit Autopilot consent.
- [x] Replace the root MIT terms with a Resonate Restricted Use License for original Resonate materials; third-party components remain governed by their own licenses.
- [ ] Audit playback/crossfade state transitions and add focused regression tests where practical.
- [ ] Verify Library search and current-row restoration, all crossfade states and presets, settings persistence, and optional spectrum fallback on target Android hardware.
- [ ] Confirm the full CI result before requesting merge.
