# Changelog

## [0.4.0] — 2026-10-07

Stable C ABI milestone for ultra-low-latency DSP on `Wire_dsp_engine`.

### Added
- `dsp_get_info()` — version, feature bitmask, max bands/frames
- `dsp_set_preamp()` — smoothed input gain [0, 4]
- `dsp_set_limiter_ceiling(high_db, low_db)` — safe range [−6, −0.1] dBFS
- `dsp_set_crossover_hz()` — LR4 split [80, 200] Hz
- Stress harness latency report (avg/max ns vs buffer budget)
- DC blocker + parameter ramps (volume, headroom, VB, preamp)
- Crest-aware release on stereo-linked true-peak limiters
- 2-band LR4 dynamics + NEON soft-path on ARM

### Safety / ULL
- No heap allocation on `dsp_process`
- Per-handle scratch buffers (64-byte aligned)
- ~4 ms look-ahead true-peak detection
- Typical CPU ~1–2% of 256-frame @ 48 kHz budget (desktop)

### Chain

```
DC → EQ → speaker/bass → headroom → preamp → DVC
  → LR4 → low/high crest-aware limiters → soft-clip
```
