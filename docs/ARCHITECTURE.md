# DSP ENGINE architecture

## Goals

- Ultra-low latency (fixed state, no RT alloc)
- Loud bass without hard clipping or image shift
- Portable C ABI

## Processing chain

```
DC-block (~8 Hz)
  → EQ → speaker/bass → partial headroom → DVC (smoothed)
  → LR4 crossover (~120 Hz)
  → low-band: gentle crest-aware stereo-linked limiter
  → high-band: tighter crest-aware stereo-linked true-peak
  → sum → soft-clip
```

## Polish

| Feature | Detail |
|---------|--------|
| **DC blocker** | 1-pole HPF ~8 Hz per channel, first in chain |
| **Parameter ramps** | Exp smooth: volume 8 ms, headroom 12 ms, virtual bass 15 ms |
| **Crest-aware release** | Transient = faster release; sustained = slower |
| **NEON** | ARM stereo soft-clip path; scalar fallback |
| **2-band LR4** | Low open ceiling; high tighter |

## Real-time rules

- `dsp_process` never allocates
- Scratch on handle
- Look-ahead ~4 ms per band detector
