# dsp_engine (Flutter / NDK)

Flutter package wrapping **DSP ENGINE v0.4** via Dart FFI and Android NDK.

Native sources live at the repo root (`include/`, `src/`). This package builds `libdsp_engine.so` with CMake.

## Use in an app

```yaml
dependencies:
  dsp_engine:
    git:
      url: https://github.com/R-6167/Resonate.git
      ref: Wire_dsp_engine
      path: packages/dsp_engine
```

```dart
import 'package:dsp_engine/dsp_engine.dart';

final engine = DspEngine.create(sampleRate: 48000, channels: 2, bufferFrames: 256);
engine.start();
engine.setEqBands(centersHz: [...], gainsDb: [...]);
engine.setVolume(1.0);
engine.setPreamp(1.0);
engine.setCrossoverHz(120);
engine.setLimiterCeiling(highDb: -0.5, lowDb: -0.2);
engine.process(inFloats, outFloats, frames);
engine.dispose();
```

## Android

NDK CMake builds the shared library from the repo-root `src/`. The plugin loads `libdsp_engine.so` so Dart FFI can resolve symbols. Process path is pure FFI (no method channel).

- minSdk 24
- ABIs: arm64-v8a, armeabi-v7a, x86_64

## Desktop / iOS

Symbols match the C ABI; ship a prebuilt library or extend CMake later. Android is the primary target for v0.4.
