# DSP ENGINE

Standalone ultra-low-latency 64-bit audio processing engine with a C ABI.

## Features

- Multi-band peaking EQ (RBJ biquads)
- Direct volume control
- Automatic headroom management
- Bass-aware true-peak limiting with 4× inter-sample detection and look-ahead
- Stereo-linked gain reduction
- Speaker mode and psychoacoustic virtual bass
- Offline bass stress harness
- No heap allocation on the audio processing path

## Layout

```
include/dsp_engine.h       Public C ABI
src/dsp_engine_core.cpp    Engine core
src/dsp_stress.cpp         Offline stress suite
tools/stress_main.cpp      CLI stress runner
docs/                      Engine design and validation notes
CMakeLists.txt             Standalone build
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

## C API

Include `dsp_engine.h` and use `dsp_create()`, `dsp_start()`, `dsp_process()`, and `dsp_destroy()`.

The engine supports both floating-point interleaved audio and an in-place PCM16 processing path.

## Validation

The built-in stress suite checks finite output, peak containment, bass-heavy cases, speaker mode, virtual bass, and transient handling.

See `docs/` for the detailed DSP notes.

## License

See LICENSE.
