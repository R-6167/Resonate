# DSP Stabilization vs Requirements Doc

| Requirement | Status |
|-------------|--------|
| 1. Automatic headroom | **Native** — compensates max positive band gain (~0.92×) when EQ set; extra −1.5 dB in speaker mode |
| 2. True-peak limiter | **Native** — envelope limiter, ceiling −1.0 dBFS (−1.5 speaker), attack ~2–3 ms, release ~80–120 ms |
| 3. Soft clipping | **Native** + JNI secondary net |
| 4. No RT allocations | **Done** — handle-owned filters/limiter; JNI scratch at create only |
| 5. DSP testing tools | **Partial** — offline process self-test; full sweep/xrun suite = Phase 3 |

## Chain

```
PCM → EQ → speaker/bass → auto headroom → limiter → soft clip → DVC → out
```

## Not killing potential

Headroom reduces *overall* level so the EQ *shape* (boosted bass relative to mids) stays. User raises system volume for loudness. Limiter only acts on peaks.
