#!/usr/bin/env python3
"""Harden playback controls vs crossfade edge cases."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
mp = ROOT / "lib/providers/music_provider.dart"
t = mp.read_text()

# 1) canCrossfadeNext must require effectiveCrossfadeEnabled
old_can = """  bool get canCrossfadeNext {
    if (_crossfadeInProgress || _queue.isEmpty || _queueIndex < 0) return false;
    if (_repeatMode == PlaybackRepeatMode.one) return false;
"""
new_can = """  bool get canCrossfadeNext {
    if (!effectiveCrossfadeEnabled) return false;
    if (_crossfadeInProgress || _queue.isEmpty || _queueIndex < 0) return false;
    if (_repeatMode == PlaybackRepeatMode.one) return false;
"""
if old_can in t:
    t = t.replace(old_can, new_can, 1)
    print("canCrossfadeNext + effective")
else:
    print("WARN canCrossfadeNext")

# 2) _cancelAutomaticPlaybackWork — never hard-silence Engine B when B is active
old_cancel = """  void _cancelAutomaticPlaybackWork() {
    // Invalidate all in-flight automatic A/B work before starting the user's
    // transport operation. Old futures may still unwind, but cannot commit.
    _userTransportEpoch++;
    _automaticTransitionGeneration++;
    _automaticCrossfadeInFlight = false;
    _crossfadeInProgress = false;
    _completionAdvanceInProgress = false;
    _completionObservedDuringCrossfade = false;
    _preloadedNextSongId = null;
    _crossfadePreloadInFlight = false;
    // Hard-silence the idle engine so a dying crossfade cannot keep audible B.
    unawaited(() async {
      try {
        await _playerB.pause();
      } catch (_) {}
      try {
        await _playerB.setVolume(0.0);
      } catch (_) {}
      try {
        await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
      } catch (_) {}
    }());
"""

new_cancel = """  void _cancelAutomaticPlaybackWork() {
    // Invalidate all in-flight automatic A/B work before starting the user's
    // transport operation. Old futures may still unwind, but cannot commit.
    _userTransportEpoch++;
    _automaticTransitionGeneration++;
    _automaticCrossfadeInFlight = false;
    _crossfadeInProgress = false;
    _completionAdvanceInProgress = false;
    _completionObservedDuringCrossfade = false;
    _preloadedNextSongId = null;
    _crossfadePreloadInFlight = false;
    // Silence the *idle* engine only. Hardcoding Engine B used to mute playback
    // after a committed A→B handoff when the user paused/skipped (active was B).
    unawaited(() async {
      try {
        final idle = inactivePlayer;
        final active = audioPlayer;
        final master = _eqPreampScale.clamp(0.05, 1.0);
        try {
          await idle.pause();
        } catch (_) {}
        try {
          await idle.setVolume(0.0);
        } catch (_) {}
        try {
          await _clearDjStretchSpeeds(outgoing: active, incoming: idle);
        } catch (_) {}
        // Keep the active engine audible at master if the user still wants play.
        try {
          if (_userWantsPlaying && active.volume < master * 0.5) {
            await active.setVolume(master);
          }
        } catch (_) {}
      } catch (_) {}
    }());
"""

if old_cancel in t:
    t = t.replace(old_cancel, new_cancel, 1)
    print("cancel idle-only")
else:
    print("WARN cancel block")

# Remove duplicate idle silence at end of cancel if it still hardcodes patterns
# The original also has a second unawaited idle block — leave it (uses inactivePlayer)

# 3) seek during transition — cancel automatic work first so we don't seek outgoing mid-fade
old_seek = """  Future<void> seek(Duration position, {String source = 'normal_player'}) {
"""
# Find seek method start and inject cancel after intent
if "command: 'seek'" in t and "_cancelAutomaticPlaybackWork();" not in t[
    t.find("Future<void> seek(Duration position") : t.find("Future<void> seek(Duration position") + 400
]:
    # insert after method open
    needle = "  Future<void> seek(Duration position, {String source = 'normal_player'}) {\n"
    # Look for body structure
    idx = t.find(needle)
    if idx < 0:
        print("WARN seek method")
    else:
        # Find intentToken issue line nearby
        chunk = t[idx : idx + 500]
        if "_cancelAutomaticPlaybackWork()" not in chunk:
            # insert after intentToken if present
            if "_playbackIntentGate.issue()" in chunk:
                t = t.replace(
                    "  Future<void> seek(Duration position, {String source = 'normal_player'}) {",
                    "  Future<void> seek(Duration position, {String source = 'normal_player'}) {\n"
                    "    // Seeking mid-crossfade must kill the fade so we don't move the wrong engine.\n"
                    "    if (_crossfadeInProgress ||\n"
                    "        _automaticCrossfadeInFlight ||\n"
                    "        _repeatSelfHandoffInFlight) {\n"
                    "      _cancelAutomaticPlaybackWork();\n"
                    "    }",
                    1,
                )
                print("seek cancels transition")
            else:
                print("WARN seek structure")

# 4) After cancel path in nextSong — ensure active volume restored is covered by cancel fix

# 5) Document audit notes in docs
audit = ROOT / "docs/PLAYBACK_CROSSFADE_AUDIT.md"
audit.write_text("""# Playback controls & crossfade audit (modes_on_dj_v2)

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
"""
)

mp.write_text(t)
print("harden done")
