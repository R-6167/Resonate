# Advanced DSP and DVC implementation plan

Status: architecture audit complete; implementation plan only. Do not treat UI state as proof that an effect is active.

## Summary

Resonate already has a substantial in-house native DSP path. The intended live route is:

`EqualizerProvider` / output-route policy
→ `AudioEffectsBridge` (`com.aetherion.resonate/audio_effects`)
→ `AudioEffectsChannelHandler`
→ `LiveDspChannelHandler`
→ `DspEngineRegistry`
→ per-player `DspEngineAudioProcessor`
→ JNI (`dsp_jni`) and native engine (`dsp_engine`).

`scripts/patch_just_audio_dsp_sink.py` injects the processor into the `just_audio` Android sink. Each A/B player must have its own processor/handle; the registry carries settings forward when the second engine appears. Native processing is designed to fail open to unmodified PCM when the processor fails.

## Audit findings

### Connected today

- `MainActivity` registers `AudioEffectsChannelHandler` on `com.aetherion.resonate/audio_effects`.
- `AudioEffectsChannelHandler` delegates live DSP methods to `LiveDspChannelHandler`; the latter maps preamp, EQ bands, limiter ceiling, crossover, speaker mode, virtual bass, and status requests into `DspEngineRegistry`.
- `AudioEffectsBridge` exposes matching calls for those methods, and `EqualizerProvider` pushes its studio EQ curve and preamp through that bridge.
- `DspEngineSinkHook` creates one `DspEngineAudioProcessor` per injected sink. `DspEngineRegistry` applies sticky settings to newly registered A/B engines.
- Native source and build integration exist under `android/app/src/main/cpp/`; JVM tests cover processor fail-open behavior, registration inheritance, and live updates.
- The four large playback orchestration extractions are connected as Dart library parts: `music_provider_crossfade.dart`, `music_provider_transport.dart`, `music_provider_dj_handoff.dart`, and `music_provider_audio_effects_lifecycle.dart`. The parent provider declares each with a matching `part` directive. These are not orphan standalone classes.

### Gap to resolve before calling DVC user-controllable

- The current Flutter method channel exposes `setLiveDspPreampDb`, which maps to `DspEngineRegistry.applyPreampAll`. That is a DSP **preamp** control, not a separate user DVC/volume control.
- The native registry already has `applyVolumeAll` / `setVolume`, but there is no corresponding public channel/bridge method for it. The native engine comments distinguish preamp from smoothed DVC gain.
- `syncPreampToDvc` is therefore a misleading helper name: its current implementation sends a preamp command. Rename it to reflect preamp semantics when touching call sites, and add a distinct DVC API rather than reusing this path.
- `ResonateNativeDspBridge` still calls `attachResonateDsp`, `setResonateDspEnabled`, and `setResonateEqBands`; these method names are not handled by the current `AudioEffectsChannelHandler`. Those calls are swallowed by the Dart bridge, so its `available` flag and `nativeDspEnabled` toggle do not reliably describe or control the custom sink processor. Treat this as a real integration gap: re-point that bridge to the live-DSP status/EQ/master-enable APIs or retire the obsolete bridge path, then test the UI toggle against actual PCM processing. Do not blindly route the old session-attach call to a fake success response.
- The sink patch script intentionally warns and exits successfully if the upstream `just_audio` method block no longer matches. That preserves build availability, but a green APK build alone does not prove the native processor was injected. Add explicit CI evidence for the injection marker and runtime capability status; retain safe pass-through behavior for release resilience.
- The current status endpoint reports active engine count, gate state, sticky EQ/speaker settings, and native timing counters. It should be expanded carefully to distinguish `compiled`, `sinkInjected`, `nativeAllowed`, `activeEngines`, and per-engine processing/failure state. Zero active engines while stopped is not itself a failure.

## Supported architecture for advanced controls

### 1. One canonical DSP settings model

Create a typed, versioned settings model in Dart with independent fields for:

- master DSP enable/bypass;
- EQ enabled state, band centers, gains, and preset identity;
- **preamp gain** (dB), including optional automatic EQ headroom;
- **DVC/master digital gain** (dB or linear value, but one canonical stored unit);
- limiter ceiling / protection settings;
- speaker protection and virtual-bass amount;
- optional future effects only after their processing path is implemented and tested.

Clamp and validate at the model boundary. Persist a versioned JSON/settings schema, migrate existing preferences, and serialize updates so rapid slider changes cannot reorder older asynchronous writes over newer ones. Avoid two competing sources of truth across `EqualizerProvider`, `AudioEffectsProvider`, and native sticky state.

### 2. Keep preamp and DVC separate end-to-end

- Keep `setLiveDspPreampDb` mapped to `applyPreampAll`; rename the Dart helper currently called `syncPreampToDvc` to `syncPreampToNativeDsp` (or equivalent) and update call sites.
- Add a distinct channel method such as `setLiveDspDvcDb` and bridge method, mapping to a dedicated registry operation that converts dB to linear gain and calls `applyVolumeAll`.
- Define DVC semantics explicitly: master digital gain before the output, with bounded range and a short native ramp. Do not silently couple it to EQ preamp, Android `LoudnessEnhancer`, player volume, or crossfade ramp volume.
- Decide whether DVC should be applied before or after the limiter based on native signal flow and clipping tests; document the chosen signal order. Do not claim true peak limiting unless the implementation measures/protects true peaks.
- During crossfade, apply the same user DSP/DVC profile to both engines, but leave transition-envelope gain owned by crossfade orchestration. These are separate gain stages and must not overwrite each other.

### 3. Capability-aware UI, not fake toggles

Add an Audio Lab/DSP section with:
- DSP engine status and a clear bypass switch;
- EQ curve, band controls, preset save/restore;
- separate Preamp and DVC controls with current values and reset actions;
- protection controls (limiter/speaker mode) only where the native path supports them;
- output-route-aware explanation for speaker/headphone/Bluetooth/car behavior;
- capability states: Available, Active, Temporarily unavailable, and Safe pass-through.

When native injection is unavailable, keep playback alive and explain that the advanced native processing is inactive. Do not make the UI show an effect as active merely because its preference was saved.

### 4. One effect owner per stage

- Keep Resonate native DSP as the owner of studio EQ, preamp, DVC, speaker protection, virtual bass, and limiter once each is implemented in the native path.
- Do not stack Android hardware Equalizer, DynamicsProcessing, BassBoost, or LoudnessEnhancer on top of the same function. Use platform effects only as an explicit fallback with a reported capability mode, not concurrently with the native equivalent.
- Route policy may propose a profile, but explicit user overrides should have defined precedence and should not be rewritten silently on every route event.

### 5. Registry concurrency and native lifecycle

- Registration, unregistration, and sticky-setting updates must be serialized under the same registry lock. Otherwise an update can miss a handle while it is being configured but not yet published.
- Configure a new handle from one coherent sticky settings snapshot before publishing it.
- Keep JNI/native calls off the audio processing callback for UI updates; the processor should only consume already-published native parameters.
- Keep fail-open behavior local to the failing processor. A/B engine failure must not disable the other engine or strand playback.
- Expose and test parameter ranges and reject malformed arrays (especially mismatched EQ center/gain lengths) at the channel boundary.

## Phased implementation and acceptance criteria

### Phase A — Integration verification and hardening
- Serialize registry register/unregister/update operations.
- Test that a concurrent new engine inherits the latest setting generation.
- Make CI report whether the `just_audio` sink patch was applied; do not infer injection from APK compilation alone.
- Verify status reporting with playback stopped, one engine active, two engines active, and native DSP disabled/failing.
- Keep the current playback path and defaults unchanged.

### Phase B — DVC as a distinct control
- Add the separate bridge/channel/registry call and versioned persisted setting.
- Add native unit tests for clamp, unity gain, mute/attenuation, and ramp behavior.
- Verify DVC and preamp independently and together, including EQ boosts and limiter behavior.
- Verify A/B engines receive the same setting after engine creation and during crossfade.

### Phase C — Advanced DSP control surface
- Wire Audio Lab to the canonical settings model.
- Expose only effects that have a working native implementation and observable status.
- Save/load custom profiles; reset and bypass must restore predictable values.
- Confirm no redundant Android effect attaches or duplicated gain stages.

### Phase D — Regression and device validation
- Flutter analyze/tests, Kotlin/JVM DSP tests, native stress tests, Android build, and release APK build all pass.
- Device checks: play/pause/seek/next; repeated slider movement; switch songs/modes; crossfade; screen off; wired and Bluetooth route changes; unplug/reconnect; process restart; native DSP fault/pass-through.
- Check for clipping, unexpected gain jumps, stale settings on Engine B, CPU/latency overruns, and leaks after repeated player creation/disposal.
- Do not claim hardware validation from CI alone; record actual device and output-route results separately.

## Implementation order

1. Finish the registry race hardening and verify CI.
2. Repair or retire the disconnected `ResonateNativeDspBridge` session/toggle calls and verify that the UI reflects real sink processing.
3. Add explicit sink-injection verification/status.
4. Correct the preamp/DVC naming mismatch.
5. Implement DVC as a separate end-to-end control.
6. Build Audio Lab UI over the typed settings model.
7. Add profiles/automation only after the controls are stable and testable.

Keep each phase a small PR. Avoid another broad rewrite of `MusicProvider`; keep transport/crossfade gain envelopes and DSP user gain independently owned.
