# DSP + dual playback engines (A / B)

Resonate crossfade uses **two** `just_audio` / ExoPlayer instances. Live DSP must match that model.

## Rule

| Principle | Detail |
|-----------|--------|
| **1 handle per sink** | Each player gets its own `DspEngineAudioProcessor` and its own `dsp_create` handle |
| **Never share** | Do not call `dsp_process` on the same handle from two audio threads |
| **Same config** | Both engines use the same sample rate / channel count / EQ / DVC targets |
| **Fail-open** | Any native failure → pass-through PCM; session gate can ban further creates |
| **UI broadcast** | Preamp/EQ later applied to **all** registered handles via `DspEngineRegistry` |

## Lifecycle

```
just_audio player A  →  createProcessors()  →  Processor#1  →  engine handle A
just_audio player B  →  createProcessors()  →  Processor#2  →  engine handle B

Crossfade: both sinks active, each process() on its own handle
After handoff: idle player may onReset() → destroy its handle; registry updates
```

`DspEngineSinkHook.createProcessors()` is invoked per player construction (patched just_audio). Registry `activeCount` of 0–2 is normal.

## Fail-open (`DspSessionGate`)

1. `nativeCreate` returns 0 or throws → count failure; after **2** → session trip.
2. `process` returns non-zero repeatedly → **local** demote that processor to pass-through.
3. Tripped session → all new injects are pass-through; **playback continues**.
4. SIGSEGV cannot be caught in Kotlin — ABI must stay matched to `dsp_engine.h`.

## Flawless crossfade checklist

- [x] Independent processors per player
- [x] Session gate + local demote
- [x] Format change destroys/recreates one handle
- [ ] Dart preamp → `dsp_set_volume` on all handles (JNI expose + MethodChannel)
- [ ] Dart EQ bands → `dsp_eq_set_bands` on all handles
- [ ] Diagnostics event when gate trips / demote
- [ ] Stress: A↔B handoff every track for 30+ minutes

## Why not one shared engine?

A single `dsp_process` graph cannot run two interleaved PCM streams without mixing. Crossfade needs **two** decoded streams mixed by player volumes (or a custom mixer). Keeping DSP **per stream** preserves bit path and avoids lock contention on the audio thread.

## OEM notes

Some devices mis-report channel count or reconfigure mid-stream. Processor treats rate/channel change as recreate. If create fails after change, that sink falls back to pass-through only.
