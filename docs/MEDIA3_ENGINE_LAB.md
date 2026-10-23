# Media3 Engine Lab — device validation

The single-player lab lives on `media3-engine-lab`; the two-deck experiment lives on the separate `media3-crossfade-lab` branch. It must not be merged into `Resonate-True-Apk` until the Media3 service passes the device checklist below and the remaining parity work is explicitly reviewed.

## Safety boundary

- Open **Settings → Developer tools → Media3 Engine Lab** or **Media3 Crossfade Lab** in a **debug build**.
- The entry is guarded by Flutter's `kDebugMode`; it is not shown in profile/release builds.
- Opening Resonate does not connect to Media3. Entering the lab alone does not start playback; selecting a file connects the native service and prepares that file. Playback begins only when Play is pressed.
- The lab uses the experimental Media3 service and does not replace or call `MusicProvider`. The production `just_audio` playback path remains unchanged.
- Leaving the lab requests stop for the lab player only.

## Getting an installable debug APK

After the experimental branch CI run succeeds, open that GitHub Actions run and download the `media3-engine-lab-debug-apk` artifact. Install `app-debug.apk` on the test device. This is a development build, not a release APK; keep it for validation only.

## Test sequence

1. Install a debug APK built from `media3-engine-lab`.
2. Open **Settings → Developer tools → Media3 Engine Lab**.
3. Choose a local audio file. The file picker may supply an app-readable cache path; the lab passes that path to Media3 as a file URI. Confirm the selected filename appears and the native state reaches **Ready**.
4. Press Play; verify audible playback and that the state changes to playing.
5. Pause, resume, seek to a different position, change volume, and Stop. Check the displayed position/state and note any error text.
6. With Media3 playing, send Resonate to the background and lock the screen. Inspect the Android media notification/lock-screen controls.
7. Test notification play/pause/seek, wired headset controls, Bluetooth play/pause, Bluetooth disconnect/reconnect, and an audio-focus interruption. Record actual results; do not assume these controls are connected just because the service compiles.
8. Repeat on the oldest supported Android device (especially Android 7). Record model, Android version, file format, whether audio starts, any errors, and approximate memory usage.
9. Reopen the lab and confirm it can load and play another file after Stop and after returning from the background.

## Report template

- Device model / Android version:
- Build commit:
- File format / approximate duration:
- Load / prepare:
- Play / pause / resume:
- Seek / stop / volume:
- Background / lock screen:
- Notification controls:
- Headset / Bluetooth:
- Audio-focus interruption:
- Errors shown:
- Approximate memory use:

## Current limitations

The single-player lab validates the native playback vertical slice. The separate crossfade lab adds a first dual-deck prototype with an equal-power gain ramp, but does not yet establish production-grade transition cancellation under all races, queue/metadata parity, DSP and leveling integration, spectrum extraction from Media3 output, full external-control parity, or acceptable resource use. The fade prototype is experimental. Master volume is now composed with the per-deck crossfade envelope, and cancelling/completing a fade should restore the chosen master volume rather than force full volume. Track leveling/preamp, sleep fade, and audio-focus ducking are not yet composed into this native policy. Do not cut production over based on this screen or CI alone.

## Merge gate

Keep the pull request Draft and target `media3-native-engine`, not `Resonate-True-Apk`, until:
- CI is green;
- the single-player device checklist is completed and reviewed;
- the dual-deck crossfade prototype passes device stress tests, including cancel/skip/restart during a fade;
- Android 7 compatibility and memory use are acceptable;
- notification, headset, Bluetooth, and audio-focus results are recorded;
- remaining parity gaps have a tested plan.


## Dual-deck crossfade lab

On `media3-crossfade-lab`, open **Settings → Developer tools → Media3 Crossfade Lab**:

1. Choose a current track and press **Play current**.
2. Choose an incoming track. Wait until the incoming deck reports **Ready**.
3. Select a fade duration and press **Crossfade now**.
4. Listen for volume dips/spikes, gaps, overlapping voices, or the wrong track remaining active.
5. During separate runs, lower the master volume before the fade, change it during the fade, press **Cancel**, start a second transition, pause/stop during a fade, and lock the screen while fading. Confirm the volume never jumps to full scale on cancel or completion.
6. After a successful fade, verify notification Play/Pause and seek now control the incoming track. Load another incoming track and repeat.

The coordinator uses a cancellable 32 ms main-thread ramp and equal-power sine/cosine gain curves. This is a prototype, not the final Resonate transition engine. Report any issue with device model, Android version, duration, and the exact stress case.
