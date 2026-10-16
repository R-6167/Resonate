# DJ reliability and event-driven analysis follow-up

Target branch: `Resonate-True-Apk`

## Implemented in this pass

- DJ transition SFX tracks session-local usage by preset. When the preferred effect has already been used twice, the rack rotates to a least-used eligible effect in the same aggressiveness pool when an alternative remains under the two-use threshold.
- Idle DJ analysis is event-driven from app startup/resume, Bluetooth/audio-route changes, playback becoming idle, library scan/import changes, and a low-frequency foreground opportunity.
- Event bursts are debounced and rate-limited. Event-triggered batches are limited to 12 songs; manual/settings scans retain their larger cap.
- Cached usable profiles are skipped. Missing section profiles can be refreshed even when partial BPM/key data exists. Failed and empty results receive a six-hour retry cooldown.
- Idle analysis no longer uses `Future.timeout` to abandon a slow song and advance to the next one. Dart timeout does not cancel native decoding, so that pattern could leave work running in the background while later songs began. The service now awaits one song at a time and checks stop requests between songs.

## Remaining analysis hardening

- A playback/stop request is cooperative: if a native decode is already in progress, the current song must finish before the idle scan stops. This is intentional to avoid orphaned decode jobs and overlapping work.
- The native MediaExtractor/MediaCodec path does not yet expose cancellation. A future change should add explicit cancellation/serialization at the platform boundary and verify that late native results cannot write stale profiles.
- The six-hour cooldown for missing-section retries is in memory and resets after process restart. Persisting attempt state separately from successful analysis would make retries more predictable.
- Removing the non-cancelling timeout avoids orphaned overlapping work, but a platform call that never returns can hold the current scan open. Add native cancellation or a carefully designed watchdog that cancels the underlying operation before restoring a timeout.
- Foreground timers and lifecycle events do not guarantee work while Android has suspended or killed the app. Reliable closed-app scheduling requires a native scheduled-work mechanism (e.g. WorkManager), plus device tests and appropriate battery constraints.
- The current trigger path requires DJ Mode and “Analyze library when idle” to be enabled.

## Separate audio-focus follow-up

The user reported two calls where playback continued until manually paused. Investigate interruption events, Android audio-focus request/grant/loss callbacks, and the audio-service command path. Keep this separate from the unexplained pause at approximately 08:47, which was logged as an audio-service pause command but does not identify its origin.

## Verification required

- Unit tests: SFX usage cap/rotation, fallback when every eligible effect has reached two uses, and aggressiveness-pool restrictions.
- Analysis tests: slow analysis completes without starting overlapping song work, failed analysis does not permanently block future retries, and stop requests are respected between songs.
- Device tests: screen-off playback, app resume/unlock, Bluetooth connect/disconnect, low-end Android, and incoming calls.
- CI green is necessary but cannot prove OEM audio-focus behavior or real-world background scheduling.
