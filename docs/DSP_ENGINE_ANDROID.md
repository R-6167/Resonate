# DSP ENGINE on Android (GitHub-only workflow)

You do **not** need Android Studio. Builds run on GitHub Actions.

## What processes audio today

| Layer | Role |
|-------|------|
| **Studio curve (Dart)** | 31-band source of truth in the Equalizer UI |
| **DSP ENGINE native** | 64-bit multi-band EQ + DVC state (`libdsp_engine.so`) when packaged |
| **DynamicsProcessing** | Live multi-band on the Android audio session (API 28+), **user toggle** under Advanced |
| **AndroidEqualizer** | Device hardware band mapping (always, after playback starts) |

`just_audio` / ExoPlayer does not expose a simple PCM callback. Inserting `dsp_process()` on every buffer would require a custom audio sink. Until that exists:

- **Preamp / DVC** → DSP ENGINE (when `.so` loads) + `AndroidLoudnessEnhancer`
- **Live multi-band** → enable **Native multi-band DSP** in Equalizer → Advanced (attaches `DynamicsProcessing` only after you opt in — never on first-play critical path)
- **Hardware bands** → `AndroidEqualizer` mapped from the same studio curve

## How to use on device

1. Install the APK from Actions → **Android APK** → artifact `resonate-debug-apk` (or **Build Resonate APK** release artifact).
2. Play a track, wait ~2s for hardware EQ to bind.
3. Open **Equalizer**:
   - **Power & engine** — shows DSP ENGINE id when the native library is present.
   - **Preamp (DVC)** — knob; uses 64-bit DVC when available.
   - **Presets / Studio bands** — drive the studio curve.
   - **Advanced → Native multi-band DSP** — optional; attaches DynamicsProcessing on the current session.

Leave Advanced off if playback becomes unstable on a given OEM; hardware EQ still works.

## Build an APK without a local machine

1. Push (or open a PR) on branch `Wire_dsp_engine`.
2. Open **Actions** → workflow **Android APK** (or **Build Resonate APK**).
3. Download the APK artifact.
4. Install on a device (enable install from unknown sources if needed).

Manual re-run: **Actions → Android APK → Run workflow**.

## Logs to look for

```
DSP ENGINE ready: … (DSP-ENGINE/v0.2-eq31)
```

Equalizer → **Power & engine** should show that id when the `.so` is packaged.

## App id

`com.Aetherion.Resonate` / `com.aetherion.resonate` — DSP ENGINE is a library only.
