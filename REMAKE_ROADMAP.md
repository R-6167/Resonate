# Resonate Remake — Playback Core Roadmap

Branch: `Resonate_Remake` (from `Companion_Features_Diagnostics`)

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

### Phase 2 — Engine A default (next)
- Non-crossfade path stays on Engine A only
- Engine B only for crossfade / consented Autopilot preload

### Phase 5 — Intelligence optional
- Off / no consent → never calls play APIs
- Graduated + consent → enqueue / playNext / optional B preload only via public APIs

### Phase 6 — Cleanup + smoke checklist
