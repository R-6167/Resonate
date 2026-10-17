# DJ reliability and event-driven analysis follow-up

Target branch: `Resonate-True-Apk`

## Implemented in this pass

- DJ transition SFX tracks session-local usage by preset. When the preferred effect has already been used twice, the rack rotates to a least-used eligible effect in the same aggressiveness pool when an alternative remains under the two-use threshold.
- Follow-up hardening invalidates in-flight one-shot sample startup when a transition restores, prevents a delayed sample/track echo from starting after cancellation, and serializes overlapping SFX engagement by restoring the prior effect first. Restore also reopens the track-manipulation gate immediately, so a cancelled repeat/stutter/brake action cannot leave later SFX permanently blocked.
- Idle DJ analysis is event-driven from app startup/resume, Bluetooth/audio-route changes, playback becoming idle, library scan/import changes, and a low-frequency foreground opportunity.
- Event bursts are debounced and rate-limited. Event-triggered batches are limited to 12 songs; manual/settings scans retain their larger cap.
- Cached usable profiles are skipped. Missing section profiles can be refreshed even when partial BPM/key data exists. Failed and empty results receive a six-hour retry cooldown.
- Idle analysis no longer uses `Future.timeout` to abandon a slow song and advance to the next one. Dart timeout does not cancel native decoding, so that pattern could leave work running in the background while later songs began. The service now awaits one song at a time and checks stop requests between songs.

## SFX lifecycle regression found in the 2026-10-17 diagnostics review

The new diagnostic session recorded 60 SFX events (5 delayed engagements, 1 immediate engagement, and 49 restore events). The event count alone cannot prove that every sound was audible. Code review found two lifecycle hazards worth fixing: an asynchronous one-shot could finish loading after restore and start late, and cancellation could leave the shared track-manipulation running flag set after the old action had unwound. The rack now uses a generation guard around engagement and sample startup, invalidates one-shots during restore, and clears the action gate on cancellation. Verify on-device that samples remain audible but quiet, restore occurs after every transition/interruption, and repeat/stutter/brake effects still work on subsequent transitions.

## Remaining analysis hardening

- Playback/stop requests now invalidate active and queued PCM decode jobs through a native cancellation generation. The decoder checks that generation between short MediaCodec buffer waits and releases MediaCodec/MediaExtractor in `finally`.
- Cancellation is best-effort, not instantaneous: platform setup/configure calls can still take time. The Dart analysis generation prevents subsequent windows and profile persistence after cancellation. Verify on-device that cancellation returns promptly and a later fresh scan can run normally.
- The six-hour cooldown for missing-section retries is in memory and resets after process restart. Persisting attempt state separately from successful analysis would make retries more predictable.
- The native cancellation path is cooperative and best-effort. If a platform setup call itself blocks, cancellation may not be immediate; do not reintroduce a timeout unless it also cancels the underlying operation.
- Foreground timers and lifecycle events do not guarantee work while Android has suspended or killed the app. Reliable closed-app scheduling requires a native scheduled-work mechanism (e.g. WorkManager), plus device tests and appropriate battery constraints.
- The current trigger path requires DJ Mode and “Analyze library when idle” to be enabled.

## Separate audio-focus follow-up

The user reported two calls where playback continued until manually paused. Investigate interruption events, Android audio-focus request/grant/loss callbacks, and the audio-service command path. Keep this separate from the unexplained pause at approximately 08:47, which was logged as an audio-service pause command but does not identify its origin.

## Verification required

- Unit tests: SFX usage cap/rotation, fallback when every eligible effect has reached two uses, and aggressiveness-pool restrictions.
- Analysis tests: slow analysis completes without starting overlapping song work, failed analysis does not permanently block future retries, and stop requests are respected between songs.
- Device tests: screen-off playback, app resume/unlock, Bluetooth connect/disconnect, low-end Android, and incoming calls.
- CI green is necessary but cannot prove OEM audio-focus behavior or real-world background scheduling.


## Idle-analysis cancellation classification

Diagnostics from 2026-10-17 included idle-scan events where
`stopRequestedDuringAnalysis` was true but the outcome was recorded as
`no_tags`. That conflated an intentional stop with a completed analysis that
found no usable BPM/key data, and the scan also recorded a retry cooldown.

The idle scanner now emits `outcome=cancelled` when a stop arrives during an
analysis, does not increment the failure count, and does not stamp the in-memory
retry cooldown. A genuine completed analysis with no usable tags remains
`no_tags`; an actual exception remains `failed`. This is diagnostic and retry
behavior only: it does not claim to improve BPM/key accuracy or make native
analysis cancellation instantaneous.
