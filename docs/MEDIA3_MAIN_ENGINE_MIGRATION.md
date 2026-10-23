# Media3 main-engine migration

## Intent

Make AndroidX Media3/ExoPlayer the authoritative playback engine for Resonate, then remove `just_audio` once no production path depends on it. The isolated Engine Lab demonstrated that native playback and the two-deck crossfade can sound substantially better than the current production implementation. This branch moves the work toward the real app without changing `Resonate-True-Apk`.

## Branch boundary

- Working branch: `media3-main-engine`.
- Based on the isolated Media3 crossfade lab so the known-good prototype stays available.
- Keep the migration pull request in Draft until the production provider, media session, and existing features use the same native playback authority.
- Do not merge this branch into `Resonate-True-Apk` while it is only a partial migration.

## Migration sequence

1. **Native queue/session contract (this change).** Add typed queue descriptors and metadata to the Flutter bridge, native queue loading, skip-next/previous, repeat modes, and richer immutable state snapshots. Native player objects remain inside the Android service.
2. **Single playback authority.** Refactor `MusicProvider` to issue commands to Media3 and consume Media3 state events. Avoid a dual-authority period where Flutter UI says one track is active while a different player is audible.
3. **Native crossfade and queue progression.** Replace Dart-side two-`AudioPlayer` transitions with the already tested native dual-deck transition. Preserve queue order, repeat-one/all, next/previous, preloading, cancellation, and track identity through consecutive fades.
4. **MediaSession ownership.** Make the Media3 session authoritative for notification, lock-screen, Bluetooth/headset and external transport commands. Remove duplicate playback-session ownership only after parity is verified.
5. **Audio policy and effects.** Route user volume, track leveling, EQ preamp, sleep fade, audio-focus ducking, DSP/session IDs, and visualization capture through the active Media3 output. No independent gain path may overwrite another.
6. **Remove `just_audio`.** Delete its dependency and legacy engine code only after all production imports, tests, scripts, and runtime paths have been migrated. Remove obsolete workflows or assets only when confirmed unused.
7. **Device and CI gate.** Green Flutter analysis/tests and Android debug APK build; verify consecutive crossfades, cancellation, repeat modes, queue changes, background controls, Bluetooth controls, audio focus, DSP/DVC, visualization, restore after force-stop, Android 7 behavior, and comparable memory scenarios.

## Current status

- The bridge now emits position snapshots every 250 ms while the Flutter state stream is subscribed and Media3 is playing. The ticker is stopped on pause/stream cancellation/release to avoid unnecessary background work.
- This supplies the live position updates a provider needs for the progress bar, resume persistence, listening history, and system-state mirroring; it is event plumbing, not the production provider cutover.
- Media3 single-player playback, seeking, background playback, notification controls, and an audio-focus interruption were reported clean by the user on Bluetooth.
- The user reports build #777's native two-deck crossfade sounds excellent and works correctly in their current test.
- This change adds a queue-capable bridge contract; **it does not yet make Media3 the production provider's default engine**. The provider cutover is the next required implementation step, not an assumption.
- The prototype currently applies deck gain directly to player volume. The production migration must combine crossfade gain with master volume, leveling, sleep fade and ducking before cutover.
- Keep Android 7 compatibility and low-memory performance as release requirements.
