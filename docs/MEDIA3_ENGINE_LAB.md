# Media3 Engine Lab — device validation

This is an isolated developer test path on the `media3-engine-lab` branch. It must not be merged into `Resonate-True-Apk` until the Media3 service passes the device checklist below and the remaining parity work is explicitly reviewed.

## Safety boundary

- Open **Settings → Developer tools → Media3 Engine Lab** in a **debug build**.
- The entry is guarded by Flutter's `kDebugMode`; it is not shown in profile/release builds.
- Opening Resonate does not connect to Media3. Entering the lab alone does not start playback; selecting a file connects the native service and prepares that file. Playback begins only when Play is pressed.
- The lab uses the experimental Media3 service and does not replace or call `MusicProvider`. The production `just_audio` playback path remains unchanged.
- Leaving the lab requests stop for the lab player only.

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

This lab validates only the native single-player vertical slice. It does not yet establish dual-player crossfade, queue/metadata parity, DSP and leveling integration, spectrum extraction from Media3 output, full external-control parity, or acceptable resource use. Do not cut production over based on this screen or CI alone.

## Merge gate

Keep the pull request Draft and target `media3-native-engine`, not `Resonate-True-Apk`, until:
- CI is green;
- the device checklist is completed and reviewed;
- Android 7 compatibility and memory use are acceptable;
- notification, headset, Bluetooth, and audio-focus results are recorded;
- remaining parity gaps have a tested plan.
