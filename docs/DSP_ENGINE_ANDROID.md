# DSP ENGINE on Android (GitHub-only workflow)

You do **not** need Android Studio. Builds run on GitHub Actions.

## What processes audio today

| Layer | Role |
|-------|------|
| **Studio curve (Dart)** | 31-band source of truth in the Equalizer UI |
| **DSP ENGINE native** | 64-bit EQ + DVC state; `dsp_process()` callable offline / self-test |
| **DynamicsProcessing** | Live multi-band on the Android session (API 28+), **user toggle** |
| **AndroidEqualizer** | Device hardware bands (after playback starts) |
| **DspEngineAudioProcessor** | media3 scaffold (pass-through); live `dsp_process` after just_audio injection |

## Locked live-buffer policy

See [DSP_JNI_BUFFERS.md](DSP_JNI_BUFFERS.md). Summary:

- **Alignment:** 64 bytes (`posix_memalign`)
- **Max block:** 4096 frames × 2 ch × 2 bytes = **16 KiB**
- **Pool:** 4 slots (64 KiB total), allocated at configure only
- **No malloc / no Dart alloc** on the audio thread

## Custom audio sink — what is / is not possible

`just_audio` owns ExoPlayer (media3) internally. It does **not** expose a hook to inject a custom `AudioProcessor` / `AudioSink`. Therefore:

| Approach | Feasible without forking? |
|----------|---------------------------|
| Live `dsp_process()` on every playback buffer | **No** — needs just_audio fork or custom player |
| DynamicsProcessing on audio session | **Yes** (current Advanced toggle) |
| AndroidEqualizer mapped from studio curve | **Yes** (default live path) |
| Offline / self-test `process()` via FFI | **Yes** (Equalizer → Advanced → Test) |
| `DspEngineAudioProcessor` class in app | **Yes** (scaffold present; not wired into player yet) |

A true live sink would:

1. Fork `just_audio` Android and register a media3 `BaseAudioProcessor` that calls `dsp_process` on the audio thread with **pre-allocated** buffers (no Dart allocs), or
2. Replace the player stack (breaks dual-engine crossfade + `audio_service`).

Until then, **live tone shaping** = hardware EQ + optional DynamicsProcessing; **DSP ENGINE** holds authoritative EQ/DVC state and is verified with the process self-test. The Kotlin processor is the RT-ready building block for step 1.

## How to use on device

1. Install APK from Actions → **Android APK** → `resonate-debug-apk`.
2. Play a track (~2s) so hardware EQ can bind.
3. Equalizer:
   - **Power & engine** — DSP ENGINE id when `.so` is present.
   - **Preamp (DVC)** — knob.
   - **Presets / Studio bands** — studio curve.
   - **Advanced → Native multi-band DSP** — optional DynamicsProcessing.
   - **Advanced → Test DSP process() path** — runs a sine through native `process()` and reports RMS.

## Build without a local machine

1. Push on `Wire_dsp_engine`.
2. Actions → **Android APK** (or **Build Resonate APK**).
3. Download artifact and install.

## App id

`com.Aetherion.Resonate` / `com.aetherion.resonate` — DSP ENGINE is a library only.
