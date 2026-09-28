# DSP ENGINE on Android (GitHub-only workflow)

You do **not** need Android Studio. Builds run on GitHub Actions.

## What processes audio today

| Layer | Role |
|-------|------|
| **Studio curve (Dart)** | 31-band source of truth in the Equalizer UI |
| **DSP ENGINE native** | 64-bit EQ + DVC state; `dsp_process()` offline + live JNI |
| **DspEngineAudioProcessor** | media3 processor on the ExoPlayer sink (after just_audio patch) |
| **DynamicsProcessing** | Optional session multi-band (Advanced toggle) |
| **AndroidEqualizer** | Device hardware bands (after playback starts) |

## Live sink injection (just_audio)

`just_audio` does not expose a public hook for custom `AudioProcessor`s. Resonate uses:

1. **`DspEngineSinkHook.createProcessors()`** — returns a `DspEngineAudioProcessor` with `nativeProcessEnabled = true`.
2. **`scripts/patch_just_audio_dsp_sink.py`** — after `flutter pub get`, patches pub-cache `AudioPlayer.java` so `DefaultRenderersFactory.buildAudioSink` calls the hook via reflection and `DefaultAudioSink.Builder.setAudioProcessors(...)`.
3. **CI** — `android-apk.yml` runs the patch before `flutter build apk`.

Local builds:

```bash
flutter pub get
python3 scripts/patch_just_audio_dsp_sink.py
flutter build apk --debug
```

Logcat on success: `Injected 1 host AudioProcessor(s) into DefaultAudioSink`.

If the hook class is missing, just_audio logs and continues without processors (safe fallback).

## Locked live-buffer policy

See [DSP_JNI_BUFFERS.md](DSP_JNI_BUFFERS.md). Summary:

- **Alignment:** 64 bytes (`posix_memalign`)
- **Max block:** 4096 frames × 2 ch × 2 bytes = **16 KiB**
- **Float scratch:** preallocated in JNI at engine create
- **No malloc** on the audio thread

## How to use on device

1. Install APK from Actions → **Android APK** → `resonate-debug-apk`.
2. Play a track; confirm logcat injection line if debugging.
3. Equalizer:
   - **Power & engine** — DSP ENGINE id when `.so` is present.
   - **Preamp (DVC)** — knob (Dart engine; live JNI engine is separate until shared handle).
   - **Advanced → Test DSP process() path** — offline FFI self-test.

## App id

`com.Aetherion.Resonate` / `com.aetherion.resonate` — DSP ENGINE is a library only.
