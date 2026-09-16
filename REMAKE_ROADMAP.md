# Resonate Remake — Playback Core Roadmap

Branch: `Resonate_Remake` (from `Companion_Features_Diagnostics`)

## Goal
Musicolet-like reliability for normal play, with Intelligence as an optional layer (not removed).

## Engine policy
- **Engine A** — primary player for normal listening
- **Engine B** — crossfade and/or Autopilot-prepared next (when consent is on)

## Phases

### Phase 0 — Contract (done in code comments)
Public APIs only: `playSong`, `playQueueIndex`, `nextSong`, `previousSong`, transport, enqueue.
Intelligence must not set engines/tokens/`isPlaying` directly.

### Phase 1 — Flexible queue (in progress)
- [x] `playQueueIndex(i)` — jump to any queue slot and play
- [x] Queue UI: every row tappable (including past)
- [x] `removeFromQueue` for non-current indices
- [ ] Library/home always start audio on tap (verify `playSong` + play retry)

### Phase 3 — Single completion path (in progress)
- [x] `onTrackEnded` → `_advanceAfterCompletion` with fresh intent token
- [x] Watchdog near end of track
- [x] Completion uses next-index play with fresh intent
- [ ] Crossfade failure falls through cleanly to `onTrackEnded`

### Phase 4 — Transport always wins (next)
- User next/pause/seek cancels auto crossfade/advance
- Play retry if native player did not start

### Phase 2 — Engine A default (after 4)
- Non-crossfade path stays on Engine A only
- Engine B only for crossfade / consented Autopilot preload

### Phase 5 — Intelligence optional
- Off / no consent → never calls play APIs
- Graduated + consent → enqueue / playNext / optional B preload only via public APIs

### Phase 6 — Cleanup + smoke checklist
