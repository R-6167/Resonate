# Resonate Modes

Modes is a **policy and session layer** on top of the existing Resonate playback
engine. It must never become a second player, focus owner, or auto-resume bully.

**Integration branch:** `modes_on_dj_v2` (DJ engine tip + Modes package).

## Architecture

```text
Canonical Library
      |
      +---------------------> Direct user playback / queues
      |
      +-> ModeContentResolver -> shelves / recommendations / Autopilot
                                  |
                           ModeProvider policy
                                  |
                     +------------+------------+
                     |                         |
                Playback adapter          UI / sessions
                     |                         |
                MusicProvider            coordinators
```

Modes emits **policy**. The host enforces it at explicit playback and
automation gates. Modes does **not** become the authority over the canonical
library.

Content folders and media classification are inputs to mode-specific generated
content. They must not hide, remove, or globally filter the user's Library when
the active mode changes. Direct user playback and explicit user-owned queues
remain accessible.

Coordinators describe session intent; they do not call `play()` directly.

## Modes

| Mode | Intent |
|------|--------|
| Normal | Legacy Resonate behavior |
| Running | Music-first, motion-aware session |
| Driving | Car context, reduced UI density, conservative automation |
| Work | Long sessions, less aggressive transitions |
| Podcast | Precise resume, speech-first, no crossfade/shuffle |
| Motivation | Speech + optional music follow-up |
| Audiobook | Precise resume, chapter-aware navigation, no crossfade/shuffle |

## Current integration status

| Area | Status |
|------|--------|
| ModeProvider + policy catalog | Complete |
| Playback port → MusicProvider policy gates | Complete |
| Crossfade / shuffle / precise-resume enforcement | Complete |
| ModeContentResolver | Complete |
| Intelligence recommendations through mode resolver | Complete |
| Autopilot through mode resolver + policy | Complete |
| Canonical Library remains mode-independent | Complete |
| Mode-aware player density / interaction policy | Integrated |
| Driving suggestion flow | Integrated |
| Podcast session lifecycle | Integrated |
| Audiobook session lifecycle + capability boundary | Integrated |
| Driving / Running / Motivation / Work coordinators | Integrated |
| Running motion decision lifecycle reset | Integrated |
| DJ × Mode crossfade authority | Integrated |
| Active automatic transition cancellation at Mode boundary | Integrated |
| User crossfade disable cancels automatic transition | Integrated |
| Harmonic Mix wiring | Integrated |
| Regression / policy test coverage | Stage D complete |
| CI / Android build gate | Green through Stage D |

## Stage D — Policy & Regression Hardening: COMPLETE

Stage D established the policy boundaries and regression coverage:

- Every current Mode publishes an explicit playback policy.
- Mode changes replace playback policy state rather than accumulating it.
- Attaching playback immediately publishes the current Mode policy.
- MusicProvider remains authoritative for actual playback behavior.
- User crossfade preference is preserved while Mode policy can gate effective use.
- Podcast/Audiobook speech policy is strict for generated content.
- DJ handoffs yield to Mode crossfade authority.
- Active automatic crossfade/preload work is invalidated when policy blocks it.
- Canonical Library/direct user queues remain outside Mode content filtering.
- Autopilot policy is isolated behind a pure policy boundary.

## Stage E — Host-Level Integration & Promotion Hardening

Stage E is **not** another expansion of the Mode policy matrix. It verifies that
the completed policy boundaries survive real host/runtime flows.

### E1 — Dynamic runtime boundaries
- [ ] Verify Mode changes during an active playback/transition session.
- [ ] Verify a blocked Mode cannot commit stale automatic A/B work.
- [ ] Verify user transport remains authoritative during automatic work.
- [ ] Verify direct Library playback and explicit user queues remain unfiltered.

### E2 — Host lifecycle coverage
- [ ] Exercise enter → playback → pause/resume → completion → exit for each
  session coordinator where applicable.
- [ ] Verify Mode changes synchronize Podcast/Audiobook session state.
- [ ] Verify Running lifecycle reset prevents stale motion decisions.
- [ ] Verify Driving suggestion/accept/dismiss does not silently take playback
  ownership.
- [ ] Verify Motivation/Work lifecycle callbacks remain suggestion/policy only.

### E3 — Promotion gate
- [ ] Green Flutter analyze/tests.
- [ ] Green native DSP tests/stress.
- [ ] Green release APK build.
- [ ] Install APK on a low-end device.
- [ ] Normal-mode parity smoke test.
- [ ] Mode switching while playing.
- [ ] Speech-mode crossfade/shuffle/precise-resume smoke test.
- [ ] Long uninterrupted playback regression.

The promotion gate is only satisfied when CI and the manual playback regression
are both green.

## Remaining product polish

These are deliberately outside Stage D and should not be confused with policy
correctness:

- Crossfade discoverability / first-run explanation.
- Richer folder badges in Library.
- Richer car/context adapters.
- Motion sensor adapter for Running.
- Home entry/polish for Modes where still absent.
- Mode-specific sleep-timer / speed-control emphasis where the UI does not yet
  expose the policy.
- Further DJ aggressiveness tuning for Driving/Work.

## Explicit non-goals

- Modes must **not** own `AudioPlayer` instances or MediaSession.
- Modes must **not** auto-resume after focus loss, phone calls, or another app's
  audio.
- Modes must **not** rewrite DJ history.
- Modes must **not** hide or globally filter the canonical Library.

## Changelog

| Date | Note |
|------|------|
| 2026-10-06 | Modes package integrated onto `modes_on_dj_v2`. |
| 2026-10-07 | Stage 0 hardening: DJ handoff gate recursion fixed, Harmonic Mix wired, CrossfadeProvider made the persisted preference authority, and canonical Library isolation clarified. |
| 2026-10-07 | Stage 1: ModeContentResolver connected to Intelligence and Autopilot generated content. |
| 2026-10-08 | Stages 2A–2F: Podcast, Audiobook, Driving, Running, Motivation, Work, playback lifecycle, Autopilot mode policy, and precise-resume boundaries integrated. |
| 2026-10-08 | Stage C: DJ × Mode interaction authority and cancellation rules hardened. |
| 2026-10-08 | Stage D: policy matrix, resolver, Autopilot, Mode→Playback, and MusicProvider regression coverage completed and CI verified green. |
| 2026-10-08 | Stage E opened: host-level integration and promotion hardening. |
