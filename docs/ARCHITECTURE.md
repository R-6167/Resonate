# DSP ENGINE architecture

## Goals

- Ultra-low latency (small buffers, fixed state, no RT alloc)
- Loud bass without hard clipping or stereo image shift
- Portable C ABI

## Processing chain

```
EQ → speaker/bass → partial headroom → DVC
  → LR4 crossover (~120 Hz)
  → low-band: gentle crest-aware stereo-linked limiter
  → high-band: tighter crest-aware stereo-linked true-peak
  → sum → soft-clip
```

## 1. Crest-aware release

- Tracks slow average of detector peak (~50 ms)
- Crest = peak / avg
- High crest (transient) → faster release
- Low crest (sustained bass) → slower release (less pumping)

## 2. NEON path

- Enabled when `__ARM_NEON` is defined (Android arm64, etc.)
- Stereo soft-clip / final stage uses NEON loads
- Scalar fallback on x86/desktop

## 3. 2-band dynamics (LR4 @ 120 Hz)

- Linkwitz-Riley 4th-order split (two Butterworth 2nd-order stages)
- **Low band**: open ceiling (−0.2 / −0.5 dB), slower release → bass can be loud
- **High band**: tighter ceiling (−0.5 / −1.0 dB) → mids/highs stay clean
- Each band stereo-linked independently

## Real-time rules

- `dsp_process` never allocates
- Scratch on handle
- Look-ahead ~4 ms per band detector
