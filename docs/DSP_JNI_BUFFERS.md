# JNI buffer strategies for live `dsp_process`

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
4. DSP ENGINE already keeps aligned `temp_l` / `temp_r`; do not add a second unbounded `std::vector` on the hot path (float→double path in `processor.cpp` still allocates — fix later for true RT).

## Pattern B — direct buffer (WebRTC-style)

```text
Setup (non-RT):
  javaDirect = ByteBuffer.allocateDirect(maxBytes)
  nativePtr  = env->GetDirectBufferAddress(javaDirect)   // cache once
  capacity   = env->GetDirectBufferCapacity(javaDirect)

Audio callback (RT):
  // use nativePtr[0..frames*ch) only — no JNI, no alloc
  dsp_process(engine, nativePtr, nativePtr, frames);     // in-place if allowed
```

`GetDirectBufferAddress` is **not** called every buffer; only when the direct buffer is created or replaced.

## Pattern C — media3 `BaseAudioProcessor` (target for live path)

```text
ExoPlayer
  └─ DefaultAudioSink
       └─ audioProcessors = [ DspEngineAudioProcessor, ... ]
            queueInput(ByteBuffer input)  // often direct, float or 16-bit
              → ensureScratch(maxFrames)  // only if format/size grew
              → dsp_process(...)
              → replaceOutputBuffer / in-place
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

1. **Dependency override / path dependency** on a thin just_audio fork that passes a custom `RenderersFactory` (small patch, ~20–40 lines in `AudioPlayer.java`).
2. Reflection hacks — fragile across media3 versions; not recommended.
3. Stay on DynamicsProcessing + hardware EQ until a fork exists.

## Recommended buffer layout for Resonate

```text
Max frames (e.g. 2048) × channels (2) × sizeof(float)

Scratch (native, aligned 64):
  in_f32[maxFrames * 2]   // if convert from PCM16
  out_f32[maxFrames * 2]  // if not in-place

Engine (dsp_create):
  temp_l / temp_r already allocated to buffer_frames * 4

On format change (sample rate / channel count):
  dsp_destroy + dsp_create with new DspConfig
  resize scratch if needed (still off audio thread or under a barrier)
```

## What to implement next (order)

1. **Native scratch pool + `DspEngineAudioProcessor` skeleton** in the app module (this repo) — process path proven without just_audio.
2. **Fix float path in DSP ENGINE** to avoid per-buffer `std::vector` when `DSP_USE_DOUBLE` is on (use preallocated double planes).
3. **Minimal just_audio patch** (or git dependency) that accepts an optional `RenderersFactory` / processor list.
4. Wire studio EQ / DVC atomics into the processor (control thread → audio thread).

Difficulty: buffer strategy **low**; media3 processor **medium**; just_audio injection **medium–high** (small fork, not a rewrite).
