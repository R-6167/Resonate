# Resonate Remake — Playback Core Roadmap

Branch: `Resonate_Remake` (from `Companion_Features_Diagnostics`)  
Also tracked on `Resonate-True-Apk` / `cleanup-docs-audit`

## Goal
Musicolet-like reliability for normal play, with Intelligence as an optional layer (not removed).

## Engine policy
- **Engine A** — primary player for normal listening
- **Engine B** — crossfade and/or Autopilot-prepared next (when consent is on)

## Phases

### Phase 0 — Contract
Public APIs only: `playSong`, `playQueueIndex`, `nextSong`, `previousSong`, transport, enqueue.
Intelligence must not set engines/tokens/`isPlaying` directly.

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

### Phase 2 — Engine A default (next priority)
**Target behaviour**
- Non-crossfade path stays on Engine A only.
- Engine B is allocated *only* for:
  - Active crossfade transitions, or
  - Consented Autopilot preload of the next track.
- After a crossfade completes, ownership returns cleanly to Engine A (or the surviving engine becomes the new A).
- No background code path may silently switch the primary engine.

**Implementation notes**
- Audit every call site that currently creates or switches engines.
- Ensure `MusicProvider` / playback coordinator treats Engine A as the default for `playSong`, `playQueueIndex`, seek, and media-session commands.
- Crossfade and Autopilot must explicitly request Engine B and release it when finished.

### Phase 5 — Intelligence optional (next priority)
**Target behaviour**
- Off / no consent → Intelligence never calls any play / queue / next APIs.
- Graduated + consent → may only enqueue / playNext / optional B preload **via public APIs**.
- Intelligence must not touch engine ownership, intent tokens, or `isPlaying` flags directly.

**Implementation notes**
- Add / strengthen a single guard at the top of Intelligence decision paths.
- Ensure `AutopilotController` and mix services respect the same consent gate.
- Add a diagnostic flag that logs any attempted play mutation when Intelligence is disabled.

### Phase 6 — Cleanup + smoke checklist
- [ ] Remove committed `android/.gradle/` caches (local step — see below)
- [ ] Split `MainActivity.kt` into focused helpers (scanning, effects, PCM, DSP bridge)
- [ ] Smoke: normal play, seek, next/prev, kill+restore, Bluetooth route change, crossfade on/off, Intelligence off/on
- [ ] Confirm no engine thrashing in logs when Intelligence is disabled

---

## Local cleanup required (Action 1 remainder)

The repository previously contained large committed Gradle caches.  
After pulling the updated `.gitignore`, run locally:

```bash
git rm -r --cached android/.gradle
git commit -m "chore: remove committed Gradle caches"
```

Then push. The new `.gitignore` will prevent them from returning.
