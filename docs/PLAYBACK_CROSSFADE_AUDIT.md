# Playback controls & crossfade audit

Branch under review: `Resonate-True-Apk` via PR #10 (`fix/repeat-one-cancel-and-mode-return`)

Audit updated: 2026-10-15

## Fixes implemented in this pass

1. **Repeat One cancellation is generation-guarded.** Turning Repeat One or crossfade off invalidates an in-flight self-handoff so a timed-out dual-engine transition cannot fall back to a stale soft loop and replay the old song.
2. **Mode boundary reconciles native loop state with ownership checks.** Audiobook's native `LoopMode.one` is not allowed to leak into Normal mode. The inactive engine is quieted and active stream subscriptions are rebound after policy changes. The synchronizer re-checks its generation, active/inactive engine identity, and transition flags after each asynchronous player operation so it cannot keep mutating an engine after a new handoff takes ownership.
3. **Repeat All is queue-driven.** Native `LoopMode.all` is disabled for the single-source player. Queue completion advances to the next song and wraps to index zero at the end.
4. **Completion suppressed during a transition is recovered.** The provider remembers which song completed during an automatic transition. When the transition exits, it checks whether the queue actually committed another song. If not, it routes the completed song back through the single completion/advance path; if it did, it only ensures the committed track continues.
5. **Preload work now has ownership checks.** A crossfade preload captures the automatic-transition generation and user-transport epoch, checks that ownership after asynchronous player operations, and avoids clearing the in-flight flag or error state belonging to a newer preload.
6. **Stale transition cleanup avoids taking ownership from newer commands.** Crossfade cancellation and repeat-self recovery are guarded so old asynchronous work does not restore volume, pause an engine, or rewrite metadata after a manual transport operation takes over.

## Intended transport rules

| User action or state | Required behavior |
|---|---|
| Repeat One + crossfade | Repeat the same song; do not advance the queue or publish another song as current |
| Disable Repeat One during self-handoff | Cancel old self-handoff; next completion follows the newly selected repeat policy |
| Repeat All | Advance through queue, then wrap to first item; never native-loop only the current source |
| Disable crossfade during preload/fade | Invalidate automatic work; do not let stale preload commit after the setting changes |
| Mode disables crossfade | No new automatic fade under the blocked policy; do not interrupt an already committed active song |
| Audiobook → Normal | Restore Normal repeat/crossfade policy and transport controls without force-stopping the app |
| Completion during an A→B transition | Advance exactly once if the fade did not commit a new queue item; otherwise continue the committed item |
| Manual Next / Previous / song selection | New user transport owns the engines; stale automatic work cannot later switch the track back |
| Pause | No automatic recovery should resume playback against the user's pause intent |
| Seek during fade | Abort/serialize conflicting transition work so the engines cannot diverge in position |

## Known risks still requiring verification

| Area | Remaining risk / next check |
|---|---|
| Android OEM / content URI behavior | `AudioPlayer` source loads and `play()` can behave differently across devices; verify on a low-end Android device and with `content://` library items |
| Gapless + crossfade | The gapless source is flattened before dual-engine fade; verify queue index, title, and audio stay aligned after several rapid skips |
| Pause/resume after Engine B becomes active | Confirm inactive-engine cleanup never mutes the active engine and resume does not resurrect the outgoing track |
| Mode switch while audio is loading | Stream rebinding and loop reconciliation must not race a new source load |
| Volume and effects | Check master volume, EQ preamp, loudness, DJ bass ducking, and fade gain are restored once—not multiplied or reset unexpectedly |
| Repeat-one edge timing | Test with short tracks and completion events arriving during both dual-engine and soft-loop fallback |
| Queue completion recovery | Test when the incoming engine load fails, times out, or completes at the same time as the outgoing engine |
| Test coverage | Provider unit tests cover mode policy gates, but full engine lifecycle and OEM behavior need integration/device tests |

## Manual regression checklist

1. Enable Repeat One and crossfade. Let Track A loop; confirm title and audio remain Track A.
2. Disable Repeat One or crossfade during the handoff. Confirm the old loop cannot reclaim playback.
3. Press Next once after that change; confirm exactly one queue step and correct title/audio.
4. Set Repeat All and play through the last queue item; confirm it wraps to the first item.
5. Switch Audiobook → Normal, then test play/pause, Next, Previous, and library selection without restarting the app.
6. Start A→B crossfade and press Next or Previous mid-fade; confirm the requested track remains active.
7. Let a track complete while crossfade is enabled, then repeat with the incoming source unavailable; confirm no stuck completion or duplicate advance.
8. After an engine handoff, adjust system volume and app volume; confirm audio remains audible and at the expected level.
9. Repeat the tests with the screen off and with local `content://` audio where available.

## Verification status

- CI previously passed for the earlier PR revision.
- The current revision must pass CI after the preload ownership guard before merge.
- CI cannot verify device-specific audio routing, OEM player timing, or actual perceived volume. Those checks remain open until run on hardware.