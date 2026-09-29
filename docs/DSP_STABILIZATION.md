# DSP Stabilization vs Requirements Doc

| Requirement | Status |
|-------------|--------|
| 1. Automatic headroom | **Native** — max positive band ×0.92; extra −1.5 dB speaker |
| 2. True-peak limiter | **Native** — ceiling −1.0/−1.5 dBFS, attack 2–3 ms, release 80–120 ms |
| 3. Soft clipping | **Native** + JNI secondary net |
| 4. No RT allocations | **Done** |
| 5a. Latency monitoring | **Phase 2** — `dsp_get_stats` / `getLiveDspStatus` (`avgUs`, `maxUs`, `overruns`) |
| 5b. Full test suite | **Phase 3** — sweeps / max-level |

## Chain

```
PCM → EQ → speaker/bass → auto headroom → limiter → soft clip → DVC → out
```

## Latency fields (getLiveDspStatus)

| Key | Meaning |
|-----|--------|
| `processCalls` | Total `dsp_process` calls |
| `avgUs` | Mean process time (µs) |
| `maxUs` | Worst-case process time (µs) |
| `overruns` | Calls slower than block duration |
| `lastFrames` | Frames in last block |
| `sampleRate` | Engine sample rate |

Healthy target: `avgUs` ≪ block time (e.g. ~10–20 ms for 512 frames @ 48 kHz → budget ~10 000 µs).
