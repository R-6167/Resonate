# DSP ENGINE

Ultra-low-latency 64-bit audio processing engine (C ABI).

> Branch `Wire_dsp_engine` is **DSP ENGINE only**.

## Features

- Multi-band peaking EQ (RBJ) + DVC
- Partial auto-headroom (preserves loud bass)
- **Crest-aware** stereo-linked true-peak limiters
- **2-band LR4** dynamics (~120 Hz split)
- **NEON** path on ARM
- Speaker mode + virtual bass
- Offline bass stress harness
- No heap allocation on the process path

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/dsp_stress_runner
```

## Chain

```
EQ → speaker/bass → headroom → DVC
  → LR4 @ 120 Hz
  → low (gentle) + high (tight) crest-aware limiters
  → sum → soft-clip
```

## License

See LICENSE.
