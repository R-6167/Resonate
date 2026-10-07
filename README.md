# DSP ENGINE

Ultra-low-latency 64-bit audio processing engine (C ABI).

> **This branch (`Wire_dsp_engine`) is DSP ENGINE only.**  
> The Resonate music player app lives on other branches (`main`, `dj_Mode`, etc.).

## Features

- Multi-band peaking EQ (RBJ biquads)
- Direct Volume Control (DVC)
- Partial auto-headroom (preserves loud bass)
- Bass-aware true-peak limiter (4× oversampling + look-ahead)
- **Stereo-linked** gain reduction (stable stereo image)
- Speaker mode + psychoacoustic virtual bass
- Offline bass stress harness
- No heap allocation on the audio process path

## Layout

```
include/dsp_engine.h       Public C ABI
src/dsp_engine_core.cpp    Engine core
src/dsp_stress.cpp         Offline stress suite
tools/stress_main.cpp      CLI stress runner
CMakeLists.txt
docs/
```

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/dsp_stress_runner
```

## Processing chain

```
EQ → speaker/bass → partial headroom → DVC → stereo-linked true-peak → soft-clip
```

## C API (sketch)

```c
#include "dsp_engine.h"

DspConfig cfg = {0};
cfg.sample_rate = 48000;
cfg.channels = 2;
cfg.buffer_frames = 256;

void* h = dsp_create(&cfg);
dsp_start(h);
dsp_process(h, in, out, frames);
dsp_destroy(h);
```

## License

See LICENSE.
