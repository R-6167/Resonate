# JNI buffer strategies for live `dsp_process`

## Locked constants (single source of truth)

| Constant | Value | Notes |
|----------|-------|-------|
| `DSP_ALIGN_BYTES` | **64** | Cache-line / NEON; min acceptable 32 |
| `DSP_MAX_CHANNELS` | **2** | Stereo for first live path |
| `DSP_MAX_FRAMES_PER_BLOCK` | **4096** | Covers 96 kHz ≈ 43 ms + headroom |
| `DSP_POOL_SLOTS` | **4** | Double-buffer + 2 jitter slots |
| `DSP_BYTES_PER_SAMPLE` | **2** | Live path PCM 16-bit (float = 4 later) |
| `DSP_MAX_BYTES_PER_BLOCK` | **16384** | `4096 × 2 × 2` |
| Pool total | **65536 bytes** | 4 × 16 KiB — allocate once at configure |

Allocation order: `posix_memalign(..., 64, size)` → Android `memalign` → `malloc` last resort.  
**Never** allocate on the audio thread / inside `queueInput`.

```c
// Reference (native header)
#define DSP_ALIGN_BYTES          64
#define DSP_MAX_CHANNELS         2
#define DSP_MAX_FRAMES_PER_BLOCK 4096
#define DSP_POOL_SLOTS           4
#define DSP_BYTES_PER_SAMPLE     2
#define DSP_MAX_BYTES_PER_BLOCK  (DSP_MAX_FRAMES_PER_BLOCK * DSP_MAX_CHANNELS * DSP_BYTES_PER_SAMPLE)
```

## Ranking (real-time audio thread)

| Strategy | Alloc on audio thread? | GC risk | Use |
|----------|------------------------|---------|-----|
| **A. Native aligned pool** (`posix_memalign`) | No (once at configure) | None | Best for DSP ENGINE scratch |
| **B. Direct `ByteBuffer` + cached address** | No | None if never reallocated | WebRTC / AudioTrack JNI pattern |
| **C. In-place on media3 buffer** | No | None | Ideal inside `BaseAudioProcessor` |
| **D. `GetPrimitiveArrayCritical`** | No | **Pins GC** — hold only microseconds | Avoid for full buffer process |
| **E. Dart `calloc` / FFI every callback** | **Yes** | High | Offline only (current self-test) |
| **F. `new float[]` / `malloc` per buffer** | **Yes** | Glitches | Forbidden |

Rules of thumb (same as WebRTC / AAudio):

1. **Allocate at setup / format change only** — never in `queueInput` / process callback.
2. Prefer **direct native memory** the audio thread already owns (media3 `ByteBuffer` or our pool).
3. **Parameter changes** (EQ gains, DVC) from the UI thread: lock-free atomics or a single SPSC command queue — not mutexes that can block the audio thread.
4. Bounds-check every block: `remaining ≤ DSP_MAX_BYTES_PER_BLOCK`.
5. DSP ENGINE already keeps aligned `temp_l` / `temp_r`; do not add a second unbounded `std::vector` on the hot path (float→double path in `processor.cpp` still allocates — fix later for true RT).

## Pattern B — direct buffer (WebRTC-style)

```text
Setup (non-RT):
  javaDirect = ByteBuffer.allocateDirect(maxBytes).order(nativeOrder())
  nativePtr  = env->GetDirectBufferAddress(javaDirect)   // cache once
  capacity   = env->GetDirectBufferCapacity(javaDirect)

Audio callback (RT):
  // use nativePtr[0..frames*ch) only — no JNI, no alloc
  dsp_process(engine, nativePtr, nativePtr, frames);     // in-place if allowed
```

`GetDirectBufferAddress` is **not** called every buffer; only when the direct buffer is created or replaced.

## Pattern C — media3 `BaseAudioProcessor` (target for live path)

Scaffold lives at:

`android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineAudioProcessor.kt`

```text
ExoPlayer
  └─ DefaultAudioSink
       └─ audioProcessors = [ DspEngineAudioProcessor, ... ]
            queueInput(ByteBuffer input)  // direct, native order
              → remaining ≤ DSP_MAX_BYTES_PER_BLOCK
              → (future) GetDirectBufferAddress + dsp_process
              → replaceOutputBuffer / in-place pass-through today
```

Injection point (Android docs):

```kotlin
object : DefaultRenderersFactory(context) {
  override fun buildAudioSink(...): AudioSink =
    DefaultAudioSink.Builder(context)
      .setAudioProcessors(arrayOf(DspEngineAudioProcessor()))
      .build()
}
```

`just_audio` builds its own `ExoPlayer` and does **not** expose this factory. Options:

1. **Dependency override / path dependency** on a thin just_audio fork that passes a custom `RenderersFactory` (small patch, ~20–40 lines).
2. Reflection hacks — fragile across media3 versions; not recommended.
3. Stay on DynamicsProcessing + hardware EQ until a fork exists.

## Recommended buffer layout for Resonate

```text
DSP_MAX_FRAMES_PER_BLOCK (4096) × DSP_MAX_CHANNELS (2) × DSP_BYTES_PER_SAMPLE (2)
  = 16384 bytes per slot × DSP_POOL_SLOTS (4) = 64 KiB total

Scratch (native, aligned 64):
  optional float plane if convert from PCM16 (same frame count)

Engine (dsp_create):
  temp_l / temp_r already allocated to buffer_frames

On format change (sample rate / channel count):
  dsp_destroy + dsp_create with new DspConfig
  resize scratch if needed (still off audio thread or under a barrier)
```

## What to implement next (order)

1. ~~Native scratch pool + `DspEngineAudioProcessor` skeleton~~ (this commit — pass-through RT-safe scaffold).
2. JNI glue: cache `GetDirectBufferAddress` once; call existing `dsp_process` from `queueInput`.
3. Fix float path in DSP ENGINE to avoid per-buffer `std::vector` when `DSP_USE_DOUBLE` is on.
4. Minimal just_audio patch (or git dependency) that accepts an optional `RenderersFactory` / processor list.
5. Wire studio EQ / DVC atomics into the processor (control thread → audio thread).

Difficulty: buffer strategy **low**; media3 processor **medium**; just_audio injection **medium–high** (small fork, not a rewrite).
