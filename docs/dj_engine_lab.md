# Resonate Advanced DJ Engine Lab

Branch: `dj_engine_lab`

This branch is an isolated development laboratory. It starts from `dj_Mode` so the existing analysis/planning code remains available as reference, but the new engine lives under `lib/services/dj_engine_lab/` and does not replace the current playback path.

## Direction

The engine is **music-aware rather than crossfade-aware**.

Pipeline:

`offline decode -> track profile -> musical structure -> transition candidates -> scoring/risk -> execution timeline -> runtime feedback -> learning`

The engine must never make playback dependent on successful DJ analysis. If analysis is missing, uncertain, corrupt, or too expensive, Resonate falls back to normal playback/crossfade.

## First foundation now present

- `DjTrackProfile`: richer musical representation than the current `DjAnalysis` row.
- `DjTransitionBrain`: generates multiple transition candidates instead of immediately selecting one heuristic strategy.
- `DjExecutionPlanner`: converts a selected candidate into an engine-neutral timeline for Resonate's two audio engines.
- Risk-aware bass/energy/structure handling.

## Next layers

1. **Offline analyzer** — codec-agnostic decoded-PCM analysis; MP3/WAV/AAC/etc. are treated as input formats, not assumptions.
2. **Beat/grid engine** — beat positions, downbeats, bar/phrase grids, tempo stability, half/double-time hypotheses.
3. **Structure engine** — intro/outro, build, drop, breakdown, chorus/energy changes and confidence.
4. **Spectral/risk engine** — bass collision, spectral masking, transient density, energy shock and unsafe regions.
5. **Candidate scorer** — adaptive weights by transition type and analysis confidence.
6. **Two-engine adapter** — map execution steps to Resonate's existing A/B audio engines without adding a DJ deck UI.
7. **Runtime monitor** — verify beat/tempo alignment and adapt during the transition.
8. **Learning** — learn from completed transitions, early skips, manual next, corrections and failures; not just pair success/failure.
9. **Stress/fallback tests** — malformed metadata, low-confidence analysis, long mixes, short tracks, huge BPM differences, missing files and engine failures.

## Important constraint

The advanced engine is an intelligence layer, not a playback gate. `DJ OFF`, `Intelligence OFF`, or an analysis failure must still produce normal music playback.
