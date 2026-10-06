# Resonate Modes

Modes is a **policy and session layer** on top of the existing Resonate playback
engine. It must never become a second player, focus owner, or auto-resume bully.

**Integration branch:** `modes_on_dj_v2` (DJ engine tip + Modes package).
**Package origin:** `modes_lab` (Modes-only lab branch).

## Architecture (intended)

```text
User intent / context
        ↓
Media Classifier + content folders + overrides
        ↓
ModeProvider → PlaybackPolicy + InteractionPolicy
        ↓
Host ports (playback / context / folder picker)
        ↓
MusicProvider / Autopilot / UI (consume policy only)
```

Modes emits **policy**. The host **enforces** it at a single gate (crossfade,
shuffle, resume, content bias). Coordinators describe session intent; they do
not call `play()` directly.

## Modes

| Mode | Intent |
|------|--------|
| Normal | Legacy Resonate behavior |
| Running | Music-first, large targets, two-finger interaction, motion-aware session |
| Driving | Car context, reduced UI density, conservative automation |
| Work | Long sessions, less aggressive transitions |
| Podcast | Precise resume, no crossfade/shuffle |
| Motivation | Speech + optional music follow-up |
| Audiobook | Precise resume, chapter-aware navigation, no crossfade |

## What is wired today (`modes_on_dj_v2`)

| Item | Status |
|------|--------|
| `lib/modes/**` package (models, coordinators, catalog, tests) | Present |
| `ModeProvider` registered in app graph | Present |
| `ResonateModeContextPort` (Bluetooth car → driving suggest) | Present |
| `ResonateModePlaybackPort` → soft gates on `MusicProvider` | Present |
| `ResonateModeFolderPickerPort` (FilePicker directories) | Present |
| Settings → Playback → Modes screen | Present |
| Mode chip on Now Playing + Home | Present |
| Policy soft-gates: crossfade / shuffle / precise resume | Present |
| Autopilot content bias (`isAcceptableForAutopilot`, bias score) | Present |
| Crossfade engine path (user toggle + mode allow) | Present (default **off**) |
| DJ engine, EQ, glass UI, library, queue | Present (from DJ base) |

## Missing features

These are **specified or packaged** but **not productized** on the integration
branch. This list is the backlog before Modes can feel “complete” next to the
rest of Resonate.

### P0 — Playback confidence

- [ ] **Crossfade discoverability** — engine defaults to crossfade off; many
  builds feel “broken” until Settings → Crossfade is enabled with duration &gt; 0.
  Consider a sensible first-run default (e.g. 3s) or an onboarding hint.
- [ ] **Mode vs Crossfade UI honesty** — when policy sets `crossfadeAllowed:
  false` (Podcast / Audiobook), the Crossfade screen can still look “on” while
  the engine refuses transitions. Surface “blocked by Mode” in UI.
- [ ] **Single source of truth for crossfade prefs** — `CrossfadeProvider` and
  `MusicProvider` both persist the same keys; keep them strictly synced and
  document which layer is authoritative for reads.

### P1 — Modes as a product surface

- [ ] **Driving suggestion UI** — `ModeProvider` already tracks
  suggest/dismiss/accept and auto-enter-on-car; **no home/player banner or
  chip** consumes it yet.
- [x] **Active mode chip on Now Playing / home** — `ResonateModeChip`; tap opens Modes.
- [ ] **`uiDensity` enforcement** — `PlaybackPolicy.uiDensity` and
  `InteractionPolicy` are not applied to player transport, lists, or settings
  density (Driving/Running large targets, reduced chrome).
- [ ] **`ModeInteractionGuard` in real UI** — Running’s two-finger / no
  long-press / no horizontal swipe contract is not enforced on player gestures.
- [ ] **Classifier on the play path** — folder routing and overrides are stored,
  but library play / next / Autopilot do not consistently resolve
  `ModeMediaItem` + classifier before queue decisions (beyond soft Autopilot
  bias).

### P1 — Session coordinators (package exists, host does not call them)

None of these coordinators are invoked from `MusicProvider`, player lifecycle,
or mode enter/exit today:

- [ ] **`PodcastCoordinator`** — session boundaries, precise resume handoff to
  engine, no-crossfade confirmation.
- [ ] **`AudiobookCoordinator`** — same family as podcast; chapter-aware nav
  policy unused in UI.
- [ ] **`DrivingCoordinator`** — car context intents beyond suggest flag;
  couple with transport target sizing.
- [ ] **`RunningCoordinator` + `RunningSessionController` +
  `RunningMotionDecision`** — movement states (unknown / stationary / stopped /
  moving); host must supply motion; brief stop must not pause.
- [ ] **`MotivationCoordinator`** — speech started/completed and music
  follow-up suggestions.
- [ ] **`WorkCoordinator`** — long-session bias and reduced transition
  aggressiveness beyond static policy flags.

### P2 — Context and input adapters

- [ ] **Motion / activity port** — Running is sensor-agnostic by design; no
  host adapter feeds `MotionState` yet.
- [ ] **Richer car context** — today car is Bluetooth-name / type heuristics
  only; optional route service alignment with Modes context is incomplete as a
  single API.
- [ ] **Folder categories in library UX** — folder assignment lives under Modes
  settings only; library rows do not show “Podcast folder” / override badges.

### P2 — Intelligence and automation

- [ ] **Autopilot + Modes authority audit** — bias is fail-open; Modes must not
  regain the ability to force play after user pause or external focus loss
  (keep ports soft-only).
- [ ] **DJ + Modes interaction rules** — document when DJ handoffs yield to
  Podcast/Audiobook no-crossfade policy and when DJ aggressiveness is clamped
  in Driving/Work.
- [ ] **Sleep timer / speed controls emphasis** — policy flags
  (`sleepTimerSuggested`, `speedControlsEmphasized`) are not reflected in
  player chrome per mode.

### P3 — Polish and docs

- [ ] **Modes entry from home** — not only Settings → Playback.
- [ ] **End-to-end tests** — host-level tests for policy gates (crossfade blocked
  in Podcast, shuffle blocked, precise resume on/off) on `MusicProvider`.
- [ ] **Promote path** — checklist to merge `modes_on_dj_v2` → `dj_engine_v2`
  only after P0–P1 and a green APK + manual Normal-mode parity test.

## Explicit non-goals

- Modes must **not** own `AudioPlayer` instances or MediaSession.
- Modes must **not** auto-resume after focus loss, phone calls, or another app’s
  audio (focus yield stays in the playback/session layer).
- Modes must **not** merge by rewriting DJ history; keep surgical integration on
  top of the stable DJ tip.

## Related docs

- `docs/dj_engine_v2.md` — DJ engine behavior on the same line of development.
- Branch `modes_lab` — pure Modes package + unit tests (no full app).

## Changelog (integration)

| Date | Note |
|------|------|
| 2026-10-06 | Package copied onto `modes_on_dj_v2`; ports + ModeProvider + Autopilot bias; missing-features section added. |
