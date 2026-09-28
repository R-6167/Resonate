# JNI buffer strategies for live `dsp_process`

## Locked constants (single source of truth)

| Constant | Value | Notes |
|----------|-------|-------|
| `DSP_ALIGN_BYTES` | **64** | Cache-line / NEON; min acceptable 32 |
| `DSP_MAX_CHANNELS` | **2** | Stereo for first live path |
| `DSP_MAX_FRAMES_PER_BLOCK` | **4096** | Covers 96 kHz ≈ 43 ms + headroom |
| `DSP_POOL_SLOTS` | **4** | Double-buffer + 2 jitter slots (doc); live path uses 1 in + 1 out float plane |
| `DSP_BYTES_PER_SAMPLE` | **2** | Live path PCM 16-bit (engine ABI is float) |
| `DSP_MAX_BYTES_PER_BLOCK` | **16384** | `4096 × 2 × 2` |
| Float scratch | **32768 bytes × 2** | `4096 × 2 × 4` in + out, 64-byte aligned |

Allocation order: `posix_memalign(..., 64, size)` → Android `memalign` → `malloc` last resort.  
**Never** allocate on the audio thread / inside `queueInput`.

## Implemented path (this branch)

```text
libdsp_jni.so  (Resonate app)
  dlopen → libdsp_engine.so  (Flutter plugin)
  nativeCreate → dsp_create + start + float scratch
  nativeProcessPcm16Direct:
      GetDirectBufferAddress (cached per jobject identity)
      PCM16 → float scratch_in
      dsp_process(engine, scratch_in, scratch_out, frames)
      float → PCM16 → out direct buffer

DspEngineAudioProcessor.queueInput
  → if nativeProcessEnabled && handle ≠ 0 → JNI process
  → else identity put()
```

Kotlin entry: `com.Aetherion.Resonate.dsp.DspEngineJni`  
Processor: `com.Aetherion.Resonate.dsp.DspEngineAudioProcessor`

## Ranking (real-time audio thread)

| Strategy | Alloc on audio thread? | GC risk | Use |
|----------|------------------------|---------|-----|
| **A. Native aligned pool** (`posix_memalign`) | No (once at create) | None | Float scratch in JNI |
| **B. Direct `ByteBuffer` + cached address** | No | None if jobject stable | Implemented |
| **C. In-place on media3 buffer** | No | None | After convert via scratch |
| **D. `GetPrimitiveArrayCritical`** | No | Pins GC | Avoid |
| **E. Dart `calloc` / FFI every callback** | Yes | High | Offline self-test only |
| **F. `malloc` per buffer** | Yes | Glitches | Forbidden |

## Address caching rule

`GetDirectBufferAddress` is called only when the Java `ByteBuffer` object identity changes (`IsSameObject` fails). media3 often reuses the same direct buffers; the cache then stays hot and the RT path avoids extra JNI lookups.

## Injection still required

`just_audio` does not expose `RenderersFactory` / processor list. Until a small fork wires:

```kotlin
DefaultAudioSink.Builder(context)
  .setAudioProcessors(arrayOf(DspEngineAudioProcessor().also { it.nativeProcessEnabled = true }))
```

the processor is **not** on the live playback path. Offline `DspEngineBridge.processBuffer` remains the verification path.

## Next

1. just_audio RenderersFactory patch / dependency override.
2. Share one engine instance with Dart (EQ/DVC param sync) instead of a second `dsp_create` in JNI.
3. Optional: native PCM16 process entry to skip convert when bit-perfect path allows.
