# DSP ENGINE v0.4.0

Ultra-low-latency 64-bit audio processing engine (C ABI).

> Branch **`Wire_dsp_engine`** is **DSP ENGINE only** (no Resonate app code).

## Features

- Multi-band peaking EQ (RBJ) + DVC
- Preamp + volume with parameter ramps
- DC blocker, crest-aware stereo-linked true-peak
- 2-band LR4 (80–200 Hz API)
- Configurable limiter ceilings
- NEON path on ARM
- Speaker mode + virtual bass
- Offline stress harness + latency report

## Native build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/dsp_stress_runner
```

## Flutter / NDK package

```yaml
dependencies:
  dsp_engine:
    git:
      url: https://github.com/R-6167/Resonate.git
      ref: Wire_dsp_engine
      path: packages/dsp_engine
```

See [`packages/dsp_engine/README.md`](packages/dsp_engine/README.md).

## License

See LICENSE.
