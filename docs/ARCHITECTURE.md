# Resonate Architecture

**Branch focus:** `Resonate-True-Apk` / remake work  
**Last updated:** 2026-10-17

## High-level goals

1. **Musicolet-like reliability** for normal listening (Engine A).
2. Advanced features (crossfade, Autopilot, DJ mode, Intelligence) as *optional layers* that never break the core transport path.
3. High-quality offline DSP owned by Resonate (not the system equalizer).

---

## Dual-Engine Playback Model

Resonate uses two logical engines:

| Engine | Role | When used |
|--------|------|-----------|
| **Engine A** | Primary player | All normal play, seek, next/prev, media-session commands |
| **Engine B** | Secondary / preload | Crossfade transitions and consented Autopilot next-track preload only |

### Rules (enforced by Remake Roadmap)

- Non-crossfade playback **must** stay on Engine A.
- Engine B is allocated only when:
  - Crossfade is enabled **and** a transition is about to happen, or
  - Autopilot has explicit user consent and is preparing the next track.
- Intelligence / Companion / Modes **must never** set engine ownership, tokens, or `isPlaying` directly.
- All play requests go through public APIs: `playSong`, `playQueueIndex`, `nextSong`, `previousSong`, transport controls, enqueue.

### Key components

- `PlaybackCoordinator` — serializes native source mutations; newer user requests can supersede pending ones.
- `PlaybackIntentGate` / intent tokens — prevent stale automatic work from winning over explicit user actions.
- `_cancelAutomaticPlaybackWork()` — shared cancel point used by play / toggle / pause / stop / next / prev / seek.

---

## DSP Engine (Native)

**Location**
- C++ core: `android/app/src/main/cpp/` (`dsp_engine.h`, `dsp_engine_core.cpp`, stress tests)
- Kotlin bridge & registry: `android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/`
- Dart side: `lib/dsp/` + `lib/services/resonate_dsp_pipeline.dart` + MethodChannel `com.aetherion.resonate/audio_effects`

### Processing chain (v0.4)

```
DC block → EQ → speaker / virtual bass → headroom → preamp → DVC
         → LR4 crossover → 2-band crest-aware true-peak limiter → soft-clip
```

### Live control surface (MethodChannel)

- `setLiveDspPreampDb`
- `setLiveDspLimiterCeiling`
- `setLiveDspCrossoverHz`
- `setLiveDspEqBands`
- `setLiveDspSpeakerMode`
- `setLiveDspVirtualBass`
- `getLiveDspStatus`

Controls are applied to **all active engine instances** via `DspEngineRegistry`.

### Injection path

Resonate patches `just_audio` (see `scripts/patch_just_audio_dsp_sink.py`) so that the audio sink can be intercepted and routed through the native DSP engines (A/B). This is currently a fragile but functional integration point.

---

## Intelligence / Autopilot / Companion

These layers are **optional** and must remain behind consent + feature flags.

- They may only call public playback APIs.
- They must not own engines or force `isPlaying`.
- When disabled or consent is off, they must make zero play / queue mutations.

Relevant services live under `lib/services/intelligence_*` and `lib/providers/intelligence_*`.

---

## Package & Channel Contracts

See `PACKAGE_IDENTITY.md` for the canonical applicationId and MethodChannel names.

- Media store / scanning: `com.aetherion.resonate/media_store`
- Audio effects / live DSP: `com.aetherion.resonate/audio_effects`

---

## Current status vs Remake Roadmap

| Phase | Status | Notes |
|-------|--------|-------|
| 0 — Contract | Done | Public APIs only |
| 1 — Flexible queue | Done | |
| 3 — Single completion path | Done | |
| 4 — Transport always wins | Done | |
| **2 — Engine A default** | In progress | Non-crossfade path must stay on A only |
| **5 — Intelligence optional** | In progress | Strict no-op when off / no consent |
| 6 — Cleanup + smoke | Pending | |

---

## Known fragile points

1. `just_audio` DSP sink patch (version-sensitive).
2. Large `MainActivity.kt` (scanning + permissions + PCM + effects + DSP control).
3. High number of cross-cutting providers/services → state interaction risk.

These are the main targets for the next hardening passes.
