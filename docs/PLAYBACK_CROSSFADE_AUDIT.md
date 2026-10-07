# Playback controls & crossfade audit (modes_on_dj_v2)

Date: 2026-10-07

## Fixed in this pass

1. **`_cancelAutomaticPlaybackWork` silenced Engine B always**  
   After a successful crossfade, active engine is often **B**. Pause / next /
   previous called cancel, which paused and zeroed **B** → silent playback or
   dead volume after skip. **Fix:** only silence `inactivePlayer`; restore
   active volume toward master when user still wants play.

2. **`canCrossfadeNext` ignored mode/user crossfade enable**  
   Could theoretically arm paths when `effectiveCrossfadeEnabled` was false.
   **Fix:** gate on `effectiveCrossfadeEnabled` first.

3. **Seek during crossfade**  
   Seek only moved the active (outgoing) engine while fade continued on both.
   **Fix:** cancel in-flight transition before seek when a fade is active.

## Still watch (not changed / residual risk)

| Area | Risk | Notes |
|------|------|--------|
| Dual-engine OEM load | Incoming `play()` hang | Timeouts + hard `_playSongInternal` fallback exist |
| Gapless + crossfade | Index jump | Flattened to single URI at crossfade start |
| Repeat-one + completion | Title jumps to B | Mitigated: completion suppressed for repeat-one |
| Mode Podcast/Audiobook | Crossfade force-off | Soft gate; Crossfade screen may still look “on” |
| Two-finger Running | Single finger snackbar | Does not cancel crossfade |
| `setVolume` mid-fade | Skips player volume write | Intentional; avoid fighting ramp |
| Pending next while loading | Queued next steps | Clamp 12; can feel delayed |
| DJ stretch speeds | Cancel clears | After cancel, speeds restored via `_clearDjStretchSpeeds` |
| UI title vs engine | Must track `currentSong` only after commit | Commit path updates index + song together |

## Control matrix (intended)

| User action mid-crossfade | Expected |
|---------------------------|----------|
| Pause | Cancel fade, pause both, no auto-resume |
| Next / Previous | Cancel fade, hard cut to target |
| Seek | Cancel fade, seek active engine |
| Play (resume) | No auto re-arm until playing again |
| Repeat-one near end | Self dual or soft loop; **never** advance queue |
| Mode disables crossfade | No auto-fade; gapless/hard next only |

## Manual test checklist

1. Crossfade on, play A→B: after B is active (engine chip B), **pause** — must stay silent, not dead-mute forever on resume.
2. Mid-fade **next** — immediate cut, no return to old fade target.
3. Mid-fade **seek** — fade aborts, position updates on current track.
4. Repeat-one + crossfade: title stays on same track through loop.
5. Podcast mode: no auto-crossfade even if Crossfade settings enabled.
6. After A→B, **volume rocker** and app volume still audible.
