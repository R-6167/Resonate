# DSP ENGINE on Android (GitHub-only workflow)

You do **not** need Android Studio. Builds run on GitHub Actions.

## What processes audio today

| Layer | Role |
|-------|------|
| **Studio curve (Dart)** | 31-band source of truth in the Equalizer UI |
| **DSP ENGINE native** | 64-bit multi-band EQ + DVC state (`libdsp_engine.so`) |
| **DynamicsProcessing** | Live multi-band on the Android audio session (API 28+) |
| **AndroidEqualizer** | Device hardware band mapping fallback |

`just_audio` / ExoPlayer does not expose a simple PCM callback. Inserting `dsp_process()` on every buffer would require a custom audio sink. Until that exists, **live multi-band** is applied via **DynamicsProcessing**, fed from the same studio gains that update DSP ENGINE.

## Build an APK without a local machine

1. Push (or open a PR) on branch `Wire_dsp_engine`.
2. Open **Actions** → workflow **Android APK**.
3. Download artifact **`resonate-debug-apk`**.
4. Install the APK on a device (enable install from unknown sources if needed).

Manual re-run: **Actions → Android APK → Run workflow**.

## Logs to look for

```
DSP ENGINE ready: 0.2.0-eq31 (DSP-ENGINE/v0.2-eq31)
```

Equalizer → **Power & engine** should show that id when the `.so` is packaged.

## App id

`com.Aetherion.Resonate` / `com.aetherion.resonate` — DSP ENGINE is a library only.
