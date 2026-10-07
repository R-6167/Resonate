# DSP ENGINE

Ultra-low-latency 64-bit audio processing engine (C ABI).

> Branch `Wire_dsp_engine` is **DSP ENGINE only**.

## Features

- Multi-band peaking EQ (RBJ) + DVC
- DC blocker + smoothed parameter ramps
- Partial auto-headroom (preserves loud bass)
- Crest-aware stereo-linked true-peak limiters
- 2-band LR4 dynamics (~120 Hz)
- NEON path on ARM
- Speaker mode + virtual bass
- Offline bass stress harness

## Build & verify

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/dsp_stress_runner
```

## License

See LICENSE.
