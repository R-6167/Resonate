# DSP ENGINE v0.4.0

Ultra-low-latency 64-bit audio processing engine (C ABI).

> Branch **`Wire_dsp_engine`** is **DSP ENGINE only** (no Resonate app code).

## Features

- Multi-band peaking EQ (RBJ) + DVC
- Preamp + volume with ~8 ms parameter ramps
- DC blocker (~8 Hz)
- Partial auto-headroom (preserves loud bass)
- Crest-aware stereo-linked true-peak limiters
- 2-band LR4 dynamics (default 120 Hz, API 80–200 Hz)
- Configurable limiter ceilings per band
- NEON path on ARM
- Speaker mode + virtual bass
- Offline bass stress harness + latency report

## Build & verify

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/dsp_stress_runner
```

Example output:

```text
DSP ENGINE v0.4.0 features=0x000007df maxBands=31 maxFrames=4096
bass stress: rc=0 run=12 pass=12 maxPeak=0.94…
latency: avg≈70µs budget≈5.3ms (~1.3% of budget) overruns=0
```

## Quick API

```c
#include "dsp_engine.h"

DspConfig cfg = { .sample_rate = 48000, .channels = 2, .buffer_frames = 256 };
void* h = dsp_create(&cfg);
dsp_start(h);

dsp_eq_set_bands(h, centers, gains, 10);
dsp_set_preamp(h, 1.0);
dsp_set_volume(h, 1.0);
dsp_set_crossover_hz(h, 120.f);
dsp_set_limiter_ceiling(h, -0.5f, -0.2f);  /* high, low dBFS */

dsp_process(h, in, out, frames);

DspInfo info; dsp_get_info(h, &info);
DspStats st;  dsp_get_stats(h, &st);

dsp_stop(h);
dsp_destroy(h);
```

## Layout

```text
include/dsp_engine.h   Public C ABI
src/dsp_engine_core.cpp
src/dsp_stress.cpp
tools/stress_main.cpp
CMakeLists.txt
docs/
```

## Version

| Field | Value |
|-------|-------|
| Version | **0.4.0** |
| Branch | `Wire_dsp_engine` |
| Tag | `v0.4.0` (create from this tip) |

## License

See LICENSE.
