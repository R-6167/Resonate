# Bass stress harness

Offline suite in `dsp_run_bass_stress()` — **not** on the audio thread.

## Cases

| Case | Notes |
|------|--------|
| Flat unity | Sanity |
| Bass Boost / Deep Bass / Sub Focus / Bass Extreme | 30–60 Hz full-scale sines |
| Bass Extreme + 2.0 volume | DVC before limiter |
| Speaker mode + virtual bass | HPF + VB path |
| All +12 bass | Extreme headroom path |
| Impulse | Transient |

## Pass criteria

- All samples finite (no NaN/Inf)
- `|peak| ≤ 1.001` after true-peak limiter

## How to run

Equalizer → **Advanced native path** → **Test DSP + bass stress**

Or MethodChannel `runBassStress` via `AudioEffectsBridge.runBassStress()`.
