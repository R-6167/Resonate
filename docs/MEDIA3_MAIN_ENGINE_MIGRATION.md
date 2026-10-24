# Media3 main-engine migration

## Intent

Make AndroidX Media3/ExoPlayer the authoritative playback engine for Resonate, then remove `just_audio` once no production path depends on it. The isolated Engine Lab demonstrated that native playback and the two-deck crossfade can sound substantially better than the current production implementation. This branch moves the work toward the real app without changing `Resonate-True-Apk`.

## Branch boundary

- Keep the migration pull requests in Draft until the production provider, media session, and existing features use the same native playback authority.
- Do not merge migration branches into `Resonate-True-Apk` while this is a partial migration.
- A green CI run proves build/test checks, not device parity or release readiness.

## Migration sequence

1. **Native queue/session contract (completed).** Add typed queue descriptors and metadata to the Flutter bridge, native queue loading, skip-next/previous, repeat modes, and immutable state snapshots. Native player objects remain inside the Android service.
2. **Provider-facing adapter (in progress).** Map `Song` metadata and local paths/MediaStore `content://` URIs to native queue descriptors; expose Media3 state and transport commands through a provider-facing facade. Queue start indices now resolve against the original queue after invalid paths are filtered; selecting an unplayable item is rejected rather than silently playing a different track.
3. **Single playback authority.** Refactor `MusicProvider` to issue commands to Media3 and consume Media3 state events. Avoid a dual-authority period where Flutter UI says one track is active while a different player is audible.
4. **Native crossfade and queue progression.** Replace Dart-side two-`AudioPlayer` transitions with the already tested native dual-deck transition. Preserve queue order, repeat-one/all, next/previous, preloading, cancellation, and track identity through consecutive fades.
5. **MediaSession ownership.** Make the Media3 session authoritative for notification, lock-screen, Bluetooth/headset and external transport commands. Remove duplicate playback-session ownership only after parity is verified.
6. **Audio policy and effects.** Route user volume, track leveling, EQ preamp, sleep fade, audio-focus ducking, DSP/session IDs, and visualization capture through the active Media3 output. No independent gain path may overwrite another.
7. **Remove `just_audio`.** Delete its dependency and legacy engine code only after all production imports, tests, scripts, and runtime paths have been migrated. Remove obsolete workflows or assets only when confirmed unused.
8. **Device and CI gate.** Green Flutter analysis/tests and Android debug APK build; verify consecutive crossfades, cancellation, repeat modes, queue changes, background controls, Bluetooth/headset controls, audio focus, DSP/DVC, visualization, restore after force-stop, Android 7 behavior, and comparable memory scenarios.

## Current status

- The bridge emits position snapshots every 250 ms while the Flutter state stream is subscribed and Media3 is playing. The ticker stops on pause, stream cancellation, and release to avoid unnecessary background work.
- Media3 single-player playback, seeking, background playback, notification controls, and an audio-focus interruption were reported clean by the user on Bluetooth.
- The user reports build #777's native two-deck crossfade sounds excellent and works correctly in their current test.
- The provider-facing adapter maps metadata, artwork, local file paths, and MediaStore `content://` URIs into the Media3 client contract.
- Queue-index regression tests cover invalid tracks before the selected item and rejection of a selected unplayable item.
- PR #169's master-gain/crossfade policy passed CI. It retains user master volume across fade progress, cancellation, and completion. Track leveling/preamp, sleep fade, and focus ducking still need to be composed into this same policy before production use.
- **Media3 is not yet the production provider's default engine.** `MusicProvider` still has direct `AudioPlayer` dependencies, and `just_audio` remains. The next substantial step is a dependency/call-graph audit and a deliberate provider-state migration; do not create a period where both engines can play independently.
- Keep Android 7 compatibility, low-memory performance, and device parity as release requirements.
