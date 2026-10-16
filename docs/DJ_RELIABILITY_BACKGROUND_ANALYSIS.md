# DJ reliability and event-driven analysis follow-up

Target branch: `Resonate-True-Apk`

## Implemented in this pass

- DJ transition SFX now tracks session-local usage by preset. When the preferred effect has already been used twice, the rack rotates to a least-used eligible effect in the same aggressiveness pool when an alternative remains under the two-use threshold.
- Idle DJ analysis timeout was increased from 8 to 30 seconds because the current analyzer may decode multiple windows and is expected to run on slower Android devices. This reduces premature timeout reports; it does not make a timed-out Future cancellable.

## Event-driven analysis: current implementation

The current implementation now uses a single idle-analysis service and triggers small batches from:
1. App resume/unlock.
2. Bluetooth/audio-route changes detected by the existing audio-device provider.
3. Playback transitioning to idle.
4. A low-frequency 20-minute opportunity while the app remains foregrounded.
5. The existing DJ settings/manual scan entry points.

Safeguards currently implemented:
- Event bursts are debounced and event-triggered batches are rate-limited.
- Event-triggered batches are limited to 12 analyzed songs; manual/settings scans retain their larger cap.
- Analysis is not started by these event triggers while playback is active. Starting playback requests that an in-progress idle scan stop between songs.
- Valid cached profiles are skipped.
- Missing section profiles can be re-analyzed even if a partial BPM/key result already exists.
- Failed attempts and persisted empty results receive a six-hour cooldown to prevent every unlock or route event from repeating the same expensive work.

Known limitations / next hardening:
- The six-hour cooldown for failed/empty persisted results uses the existing `analyzedAt` field; the missing-section retry cooldown is in memory and resets after process restart.
- Dart `Future.timeout` does not cancel the underlying analysis operation. A timed-out analysis may still finish in the background. The analysis pipeline needs cooperative cancellation or a serial work queue before this can be considered fully hardened.
- Library import/scan events are not yet directly wired into this coordinator.
- Foreground timers and lifecycle events do not guarantee work while Android has suspended or killed the app. Reliable closed-app scheduling requires a native scheduled-work mechanism (e.g. WorkManager), plus device tests and appropriate battery constraints.
- The current trigger path requires DJ Mode and “Analyze library when idle” to be enabled.

## Audio-focus issue (separate follow-up)

The user reported two calls where playback continued until manually paused. Investigate interruption events, Android audio-focus request/grant/loss callbacks, and the audio-service command path. Do not conflate this with the separate unexplained pause at approximately 08:47, which was logged as an audio-service pause command but does not identify its origin.

## Verification required

- Unit tests: usage cap/rotation, fallback when every eligible effect has reached two uses, and aggressiveness-pool restrictions.
- Analysis tests: slow analyzer completes without false timeout, failed analysis does not permanently block future retries, and stop requests are respected between songs.
- Device tests: screen-off playback, app resume/unlock, Bluetooth connect/disconnect, low-end Android, and incoming calls.
- CI green is necessary but cannot prove OEM audio-focus behavior or real-world background scheduling.
