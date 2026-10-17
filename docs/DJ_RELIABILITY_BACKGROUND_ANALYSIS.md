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


## Independent EQ snapshots per DJ engine

The SFX rack previously captured one equalizer gain list from engine A and
used that same list when restoring both engine A and engine B. If the engines
had different pre-transition gain states, restoring the effect could overwrite
engine B's original gains with engine A's values.

The rack now snapshots each equalizer independently before applying transition
effects and restores each engine from its own snapshot. If a snapshot cannot be
read, restoration retains the existing preference-based fallback for that
engine. CI can validate the code path, but device testing is still required to
confirm native equalizer behavior across real transitions.


## Consecutive-transition engine-state diagnostics

Crossfade commits already record that the incoming engine is playing and has
reached the target gain. That checkpoint does not show whether both reusable
engines finish cleanup at normal speed, nor whether the inactive engine is left
audible. The provider now emits `crossfade_final_engine_state` after owned
transition cleanup, including active/inactive volume, speed, playing state,
active engine, song ID, and playback intent. Use sequences of these events to
identify a stale speed or gain across consecutive transitions. The event is
observability only; it does not assert native audio is audible and does not
replace real-device testing.


## Settings performance and audio-focus controls

Settings sections can use a lightweight translucent surface without a live
BackdropFilter. The Settings hub opts into this mode to reduce repeated blur
work while scrolling, while other screens retain the existing glass-card style.
The two explanatory banners were removed from the top of Settings; the About
entry remains the home for product guidance and further information.

Audio automation now exposes persisted automatic/manual behavior and four focus
levels. All full focus-loss events still pause playback. Levels 1–2 require
manual resume; level 1 ducks notification audio more deeply. Level 3 resumes
only when focus returns after an interruption lasting at most 30 seconds; level
4 permits up to three minutes. Manual mode disables automatic ducking and resume
but retains pausing on full focus loss. Automatic system resume waits for a
stable 1.2-second window, is invalidated by a newer focus event, and no longer
calls setActive(true) as part of resume; that call could reclaim focus from
another music app. The source of an Android focus-loss event is not reliably
identified as a call versus another player, so levels 3–4 cannot guarantee
call-only resume. Level 2 is the conservative choice when yielding to other
players matters most.

Automatic EQ headroom is available as an opt-in setting. It estimates the
largest positive software EQ band and subtracts that amount from the requested
preamp, bounded by the DSP's -6 dB floor. This is a conservative heuristic, not
a measurement of actual output or clipping. It can reduce effective gain but
does not automatically boost output to compensate for EQ cuts; that would need
a separate loudness/peak model and native clipping/device validation.
