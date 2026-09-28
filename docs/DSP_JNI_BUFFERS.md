# JNI buffer strategies for live `dsp_process`

## Locked constants (single source of truth)

| Constant | Value | Notes |
|----------|-------|-------|
| `DSP_ALIGN_BYTES` | **64** | Cache-line / NEON |
| `DSP_MAX_CHANNELS` | **2** | Stereo first live path |
| `DSP_MAX_FRAMES_PER_BLOCK` | **4096** | |
| `DSP_BYTES_PER_SAMPLE` | **2** | PCM 16-bit on the wire |
| `DSP_MAX_BYTES_PER_BLOCK` | **16384** | |
| Float scratch | 2 × 32 KiB | in + out, 64-byte aligned at create |

## Live pipeline (after just_audio patch)

```text
just_audio AudioPlayer.ensurePlayerInitialized
  → DefaultRenderersFactory.buildAudioSink
       → reflection: DspEngineSinkHook.createProcessors()
       → DefaultAudioSink.setAudioProcessors([DspEngineAudioProcessor])

DspEngineAudioProcessor.queueInput (direct PCM16)
  → DspEngineJni.processPcm16Direct
       → cached GetDirectBufferAddress
       → PCM16 → float scratch → dsp_process → float → PCM16
```

Patch script: `scripts/patch_just_audio_dsp_sink.py` (run after `flutter pub get`).

## Address caching

`GetDirectBufferAddress` runs only when the Java `ByteBuffer` identity changes (`IsSameObject`). media3 often reuses buffers; the cache stays hot.

## Remaining work

1. Share one `DspEngine` handle between Dart FFI and JNI so EQ/DVC knobs affect the live path.
2. Optional permanent just_audio fork instead of pub-cache patch.
