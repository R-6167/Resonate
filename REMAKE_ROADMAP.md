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
- [ ] Split `MainActivity.kt` into focused helpers (scanning, effects, PCM, DSP bridge).
- [ ] Device smoke: normal play, seek, next/prev, kill+restore, Bluetooth route change, crossfade on/off, Intelligence off/on.
- [ ] Confirm no engine thrashing in logs when Intelligence is disabled.

## Verification status
- PR #55 synchronous consent gate is merged; its full CI run passed.
- PR #56 removed tracked Gradle cache files; its post-merge full CI/release APK run must pass before this cleanup is considered verified.
- Device-only smoke checks cannot be completed by CI alone and remain open until exercised on target Android hardware.

## Historical local cleanup instructions
The repository previously contained committed Gradle caches. PR #56 removes the tracked files; the existing `.gitignore` should keep local cache files out of future commits.
