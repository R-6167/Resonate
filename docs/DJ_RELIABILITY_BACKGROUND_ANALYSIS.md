# DJ reliability and event-driven analysis follow-up

Target branch: `Resonate-True-Apk`

## Implemented in this pass

- DJ transition SFX now tracks session-local usage by preset. When the preferred effect has already been used twice, the rack rotates to a least-used eligible effect in the same aggressiveness pool when an alternative remains under the two-use threshold.
- Idle DJ analysis timeout was increased from 8 to 30 seconds because the current analyzer may decode multiple windows and is expected to run on slower Android devices. This reduces premature timeout reports; it does not make a timed-out Future cancellable.

## Next implementation slice: event-driven background analysis

Use a single coordinator to schedule small batches when the device/app offers a quiet opportunity. Proposed triggers:

1. App becomes active after unlock / resume.
2. Bluetooth or audio-route changes.
3. Library scan/import adds or changes tracks.
4. Playback reaches a stable idle window, with low-frequency periodic opportunities while the app process is alive.
5. A user explicitly requests analysis from DJ settings.

Rules:
- Analyze only missing, stale, or unusable metadata; preserve valid cached profiles.
- Deduplicate per-song work and prevent overlapping scan loops.
- Prioritize the current song and next few queue candidates, then process the rest of the library in small batches.
- Yield between files and stop/deprioritize work when playback transitions, foreground interaction, or other high-priority work begins.
- Persist progress and last-attempt status so repeated triggers do not rescan the same failed file endlessly.
- Distinguish `no_tags`, unsupported/unreadable media, and true analyzer errors in diagnostics.
- Add bounded retry/backoff for failed tracks rather than immediately retrying on every trigger.
- Treat Android background execution honestly: lifecycle callbacks and Dart timers are not guaranteed to run after the process is suspended or killed. Reliable closed-app scheduling needs a native scheduled-work mechanism (e.g. WorkManager) and must be added only with explicit constraints and device testing.

## Audio-focus issue (separate follow-up)

The user reported two calls where playback continued until manually paused. Investigate interruption events, Android audio-focus request/grant/loss callbacks, and the audio-service command path. Do not conflate this with the separate unexplained pause at approximately 08:47, which was logged as an audio-service pause command but does not identify its origin.

## Verification required

- Unit tests: usage cap/rotation, fallback when every eligible effect has reached two uses, and aggressiveness-pool restrictions.
- Analysis tests: slow analyzer completes without false timeout, failed analysis does not permanently block future retries, and stop requests are respected between songs.
- Device tests: screen-off playback, app resume/unlock, Bluetooth connect/disconnect, low-end Android, and incoming calls.
- CI green is necessary but cannot prove OEM audio-focus behavior or real-world background scheduling.
