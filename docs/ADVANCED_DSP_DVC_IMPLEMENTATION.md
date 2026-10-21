# Advanced DSP and DVC implementation plan

Status: native DSP bridge, independent DVC control, fail-closed sink-injection CI validation, automated DVC transition/A-B regression checks, and the initial versioned DSP settings model are merged. Follow-up item 3 work adds atomic read-modify-write updates and migrates DVC, EQ, and auxiliary effect persistence onto the canonical document while retaining legacy compatibility keys. Physical-device clipping, crossfade, screen-off, and output-route checks remain outstanding. Do not treat UI state or APK compilation alone as proof that an effect is active.

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

### DVC control wiring (current implementation)

- The native engine already has a smoothed DVC gain stage separate from EQ preamp. The registry's sticky `linearGain` is applied to every newly registered A/B engine.
- PR follow-up `feat/dvc-control-end-to-end` adds `setLiveDspDvcDb` through the Flutter bridge and Android method channel to `DspEngineRegistry.applyVolumeAll`. The channel clamps requests to −24 dB through +6 dB and converts dB to linear gain; the native stage owns the gain ramp.
- Audio automation settings includes a persistent DVC slider and reset-to-unity action. DVC is stored in the canonical versioned DSP settings document and re-applied to the registry, including when no sink is currently active. Legacy DVC/EQ preferences are read during migration; compatibility keys remain while the staged migration proceeds.
- DVC remains separate from EQ preamp, Android system media volume, player volume, and crossfade envelope gain. The native processing chain applies DVC before the crossover/limiter stage, so positive gain is subject to downstream peak protection; on-device clipping and transition checks are still required.
- The misleading `syncPreampToDvc` helper has been renamed to `syncPreampToNativeDsp`; it sends only the preamp command, never DVC.
- The old `ResonateNativeDspBridge` should continue to use live-DSP status/EQ/master-enable APIs rather than resurrecting the obsolete session-attach contract.
- The sink patch script fails the build if the expected upstream patch location changes and CI separately verifies the processor-injection markers. Runtime reflection failure still logs a warning and uses the default sink, preserving playback in pass-through mode.

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

Clamp and validate at the model boundary. Persist a versioned JSON/settings schema, migrate existing preferences, and use `DspSettings.update` for serialized read-modify-write operations so concurrent controls preserve unrelated fields. Full-snapshot `save` remains for deliberate complete replacements; control-specific writers should not load a snapshot and later save it. Avoid two competing sources of truth across `EqualizerProvider`, `AudioEffectsProvider`, and native sticky state.

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
- Make CI fail if the `just_audio` sink patch cannot be applied or its required markers are absent; do not infer injection from APK compilation alone.
- Verify status reporting with playback stopped, one engine active, two engines active, and native DSP disabled/failing.
- Keep the current playback path and defaults unchanged.

### Phase B — DVC as a distinct control (implemented; verification continues)
- Add the separate bridge/channel/registry call and versioned persisted setting.
- Registry tests cover clamping and sticky gain inheritance; the native DVC transition stress test now exercises repeated target changes, peak bounds, finite output, and identical-profile A/B output consistency.
- Verify DVC and preamp independently and together, including EQ boosts and limiter behavior, on a physical device; the automated transition stress test does not replace listening/clipping checks.
- Verify A/B engines receive the same setting after engine creation and during crossfade. CI now exercises identical-profile dual-engine processing under rapid DVC target changes; actual music crossfade and screen-off behavior still require device verification.

### Phase C — Canonical DSP settings and advanced control surface
- Introduce a typed versioned DSP settings document with independent fields for master enable, EQ state/preset/bands, preamp, DVC, limiter ceiling, speaker protection, virtual bass, and supported auxiliary effects.
- Validate ranges and reject unsupported schema versions; migrate existing SharedPreferences keys without changing defaults.
- Serialize canonical document writes so asynchronous setting updates do not race each other.
- Continue migrating every settings owner to this document; avoid letting providers overwrite each other's fields from stale snapshots. DVC, EQ, and auxiliary effect persistence now use atomic updates; the EQ provider also restores its master toggle, preset, preamp, headroom, and 31-band curve from the canonical document.
- Wire Audio Lab to the canonical settings model. The EQ/Audio Lab provider now initializes from the canonical versioned document and persists the native DSP master toggle there; legacy keys remain as migration/backward-compatibility mirrors.
- Expose only effects that have a working native implementation and observable status.
- Save/load custom profiles; reset and bypass must restore predictable values.
- Confirm no redundant Android effect attaches or duplicated gain stages.

### Phase D — Regression and device validation
- Flutter analyze/tests, Kotlin/JVM DSP tests, native stress tests, Android build, and release APK build all pass.
- Device checks: play/pause/seek/next; repeated slider movement; switch songs/modes; crossfade; screen off; wired and Bluetooth route changes; unplug/reconnect; process restart; native DSP fault/pass-through.
- Check for clipping, unexpected gain jumps, stale settings on Engine B, CPU/latency overruns, and leaks after repeated player creation/disposal.
- Do not claim hardware validation from CI alone; record actual device and output-route results separately.

## Implementation order

1. Finish the registry race hardening and verify CI (completed).
2. Repair or retire the disconnected `ResonateNativeDspBridge` session/toggle calls and verify that the UI reflects real sink processing.
3. Add explicit sink-injection verification/status. (Build-time patch application and marker verification are enforced; runtime capability reporting and device checks remain.)
4. Correct the preamp/DVC naming mismatch.
5. Implement DVC as a separate end-to-end control.
6. Build Audio Lab UI over the typed settings model.
7. Add profiles/automation only after the controls are stable and testable.

Keep each phase a small PR. Avoid another broad rewrite of `MusicProvider`; keep transport/crossfade gain envelopes and DSP user gain independently owned.


## Bridge wiring repair (follow-up PR)

The legacy `ResonateNativeDspBridge` previously called `attachResonateDsp`,
`setResonateEqBands`, and `setResonateDspEnabled`, none of which were handled
by the active audio-effects channel. The bridge swallowed those missing-method
errors, which could make the UI preference look enabled without proving that
the live sink processor was available.

The repair routes the bridge through the current `getLiveDspStatus`,
`setLiveDspEqBands`, and `setLiveDspEnabled` methods. Availability is now
derived from active registered sink engines and the native safety gate; a
positive Android audio session ID alone is not treated as proof that DSP is
attached. Master enable is stored as sticky registry state and applied to newly
registered A/B engines as well as current engines. EQ-band enable remains a
separate setting. If no sink engine is registered, the bridge reports unavailable
rather than pretending a session effect was attached.

Validation should cover both JVM registry tests and merged-commit CI, followed
by device playback checks. This bridge repair does not itself expose the planned
DVC slider; DVC remains a separate follow-up that must use the registry's volume
gain, not EQ preamp or crossfade gain.


## Canonical save/restore/live-engine audit — 2026-10-21

The audit distinguishes a persisted preference from an effect that is actually
connected to the live PCM path. The following fixes restore the active native
profile from the canonical snapshot during provider initialization, before any
new sink exists: native master enable/bypass, EQ curve and enablement, DVC,
and effective preamp. Registry calls update sticky state, so subsequently
registered A/B engines inherit the profile. The provider no longer writes raw
preamp after applying automatic EQ headroom, which previously could overwrite
the calculated headroom value during initialization.

| Setting | Persistence / restore status | Live application status |
| --- | --- | --- |
| Native master enable | Canonical and legacy mirror; restored on provider initialization | Explicitly pushed to registry even with zero active sinks; sticky for future sinks |
| EQ enabled, preset, 31-band curve | Canonical snapshot and legacy mirrors; custom presets stored separately | Curve and EQ enable pushed to live registry |
| Preamp and automatic headroom | Canonical and legacy mirror; headroom restored | Effective preamp (including headroom) is awaited and pushed; no later raw-preamp overwrite |
| DVC | Canonical snapshot; legacy key used for migration | Restored to registry on provider initialization and applied to future A/B sinks |
| Reverb / virtualizer / effects-enabled | Canonical snapshot and legacy mirrors; provider loads values | AudioEffectsProvider reapplies the restored values when its bound player's Android session ID changes, and after a preference-load/session-creation race; physical-device verification is still required |
| Speaker protection / virtual bass | Model fields exist, but current live values are route policy outputs | Route service pushes values to native registry; these fields are not currently independent user controls and must not override route policy on restore |
| Limiter ceiling | Model field and native bridge/registry APIs exist | No supported user setting currently drives this field from canonical restore; leave dormant rather than silently applying a mismatched single ceiling to the native high/low limiter parameters |
| Crossover frequency | Native API exists | No canonical user setting currently owns it; native default remains in force |
| Legacy BassBoost / LoudnessEnhancer | BassBoost legacy value may remain saved; loudness is forced to zero | Both retired from active processing to avoid stacked gain/bass stages |

The model's limiterCeilingDb, speakerProtectionEnabled, and virtualBassAmount
fields are retained for schema compatibility, but they are not evidence of
active, independently configurable controls. Do not expose them as active
controls until their ownership, units, reset semantics, and live-engine status
are implemented and tested. Likewise, saved Android reverb or virtualizer
values are not proof that the platform effect has been applied to the current
playback session.

Remaining validation after CI: restart with non-default EQ/headroom/DVC/master
settings; verify both A/B engines receive the same profile during crossfade;
verify route changes reassert speaker policy; and test reverb/virtualizer
persistence across playback-session recreation. The provider now reattaches
auxiliary effects when its bound player's session ID changes, but this does not
prove the inactive A/B engine receives those platform effects. These require
device playback checks and are not inferred from Flutter/Kotlin tests alone.
