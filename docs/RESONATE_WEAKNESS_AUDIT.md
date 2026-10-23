# Resonate Weakness Audit

Baseline branch: `Resonate-True-Apk`
Audit started: 2026-10-23
Scope: reliability, misleading/no-op controls, resource use, and preservation of the Resonate sound identity.

## Evidence labels

- **Reported**: observed and reported by the user on a device.
- **Code finding**: directly visible in the inspected source; runtime impact still needs validation.
- **Hypothesis**: plausible explanation that requires reproduction or diagnostics.
- **Unverified**: not closed by CI alone; requires device testing.

## Priority register

| Priority | Area | Finding and evidence | Next action | Closure evidence |
|---|---|---|---|---|
| P0 | Crossfade continuity | **Reported:** outgoing track audibly dips for roughly 0.5–1 second before the fade. **Code finding:** the crossfade has several awaited preparation stages before the volume loop starts; DJ preparation and effect setup can run in that window. Current fade gain math alone does not establish the cause. | Capture outgoing gain at transition entry and immediately before the fade, plus preparation duration and incoming state. Use the telemetry to isolate which stage changes perceived/actual level before changing playback behavior. | Repeated device transitions with no pre-fade dip; diagnostics show no unexplained outgoing gain loss. |
| P0 | Crossfade / DJ interaction | **Code finding:** repeat/repeatRestart used to seek the outgoing player during a live fade. PR #160 removes these from automatic selection and substitutes non-seeking SFX. | Keep repeat effects disabled during crossfade until redesigned on a separate effect/player; test DJ and non-DJ transitions. | CI plus repeated device transitions without rewind/restart or silence. |
| P1 | Library on older Android | **Reported:** Android 7 library did not load songs while mode playback could play them. PR #159 conditionally queries `RELATIVE_PATH` only on API 29+ and falls back to `DATA`. | Verify permission, full library, selected folders, empty results, and rescan on Android 7. | Device test with real library and selected folders. |
| P1 | Visualization reliability | **Reported:** visualizer often fails, including across crossfade; wave shape looked malformed. PR #159 changes the renderer and adds a bounded native retry. | Test FFT freshness across track/engine/route changes and permission denial; measure UI responsiveness while capture runs. | Repeated device runs with recovery and no malformed/stale animation. |
| P1 | Visualization controls | **Code finding:** provider persists `showWaveform`, `showParticles`, `smoothAnimation`, and `frameRate`; the inspected main painter does not receive all of these values. The capture poll is fixed at about 15 Hz despite a persisted 12–30 FPS setting. Other consumers may use some settings. | Trace every setting through all consumers before removing anything; wire meaningful controls or remove misleading UI. | Each visible setting has an observable, tested effect or is removed. |
| P1 | Audio DSP settings | **Reported:** DVC worked in one test, then was later reported unwired; limiter/crossover controls previously had no audible effect. | Test UI → persistence → native registry → both engines → restore after restart/handoff. | Automated wiring tests and on-device confirmation for every exposed control. |
| P1 | Resource usage | **Reported:** average RAM use is about 150 MB. No allocation profile has been supplied, so this is a baseline, not yet proof of a leak or a problem source. | Profile idle, playback, visualizer, library scan, DJ analysis, and crossfade separately; record peak and post-task retained memory. | Before/after profile on the same device and scenario, with no playback regression. |
| P2 | Mode lifecycle | **Reported historically:** switching back to Normal could leave controls broken until force-stop/reopen. | Test repeated mode switches, queue ownership, transport commands, and session bridge teardown. | No restart needed across a repeated mode-switch matrix. |
| P2 | Playback ownership complexity | **Code finding:** MusicProvider coordinates multiple players and many extracted helpers. Extraction improves readability but shared state/lifecycle still require audits. | Trace timers, subscriptions, engine creation, cancellation and disposal; remove only proven-dead code. | No stale callbacks, duplicate work, or leaked listeners in lifecycle tests. |
| P2 | UI identity | **User direction:** preserve the ten Resonate sound identities; remove generic Bass/Genre preset concepts. | Keep identity cards, avoid generic duplicate presets, and verify controls affect the selected identity as intended. | UI review plus audible checks; no identity cards lost. |

## Crossfade diagnostic event

The current audit change adds one low-volume diagnostic event, `crossfade_pre_fade_volume_check`, per attempted transition. It records:
- outgoing volume at transition entry and just before the fade loop;
- the gain delta and elapsed preparation time;
- incoming volume/playing state and positions;
- fade duration/type and DJ/SFX state.

It deliberately does **not** force the outgoing player back to master volume, because that could undo legitimate audio-focus ducking or user volume changes. The next fix should be selected from observed stage data rather than guessing at the fade curve.

## RAM measurement protocol

Use the same device, OS version, library, and brightness/background conditions. Record:
1. cold launch after a consistent restart/settle period;
2. idle home screen;
3. normal playback for 5 minutes;
4. visualization enabled for 5 minutes;
5. library scan;
6. DJ analysis and several crossfades;
7. memory immediately after leaving those screens/tasks and after a settling period.

Capture both current/retained memory and peak memory if the profiler exposes them. Do not infer a leak from one high reading; look for growth across repeated cycles and failure to return toward baseline.

## Guardrails

- No new feature scope during this pass.
- Do not remove the ten Resonate sound identities.
- Do not sacrifice audio quality or transition correctness to lower RAM numbers.
- CI success is not a substitute for real-device validation.
- Mark a finding closed only with evidence matching its closure criteria.
