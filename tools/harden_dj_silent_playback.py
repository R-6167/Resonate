#!/usr/bin/env python3
"""Harden against silent-but-UI-alive playback (volume 0 / speed stuck / SFX stuck)."""
from pathlib import Path

MP = Path("lib/providers/music_provider.dart")
mp = MP.read_text()

# ---------- Stronger engine recover ----------
old_rec = """  /// Restore normal speed + audible volume after DJ handoff mistakes.
  Future<void> _recoverDjEngineState({String reason = 'recover'}) async {
    try {
      await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
    } catch (_) {}
    try {
      final active = audioPlayer;
      final inactive = inactivePlayer;
      final vol = _eqPreampScale.clamp(0.05, 1.0);
      try {
        await active.setSpeed(1.0);
      } catch (_) {}
      try {
        await inactive.setSpeed(1.0);
      } catch (_) {}
      try {
        if (active.playing && active.volume < 0.02) {
          await active.setVolume(vol);
        }
      } catch (_) {}
      try {
        await inactive.setVolume(0.0);
      } catch (_) {}
      await ResonateDiagnostics.recordDj(
        stage: 'engine_recover',
        outcome: 'applied',
        reason: reason,
        extra: {
          'activeVolume': active.volume,
          'activePlaying': active.playing,
          'activeEngine': _activeIsA ? 'A' : 'B',
        },
      );
    } catch (e) {
      debugPrint('DJ engine recover failed: $e');
    }
  }"""

new_rec = """  /// Restore normal speed + audible volume after DJ handoff / crossfade mistakes.
  /// Safe to call often: never throws into playback; never blocks the UI thread long.
  Future<void> _recoverDjEngineState({String reason = 'recover'}) async {
    try {
      await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
    } catch (_) {}
    try {
      await _restoreDjTransitionSfx();
    } catch (_) {}
    try {
      final active = audioPlayer;
      final inactive = inactivePlayer;
      final vol = _eqPreampScale.clamp(0.05, 1.0).toDouble();
      try {
        await active.setSpeed(1.0);
      } catch (_) {}
      try {
        await inactive.setSpeed(1.0);
      } catch (_) {}
      // Always force audible volume when we believe the user wants audio.
      // (Previously only recovered when volume < 0.02, which missed ~0.03–0.05 mutes.)
      try {
        if (_userWantsPlaying || active.playing) {
          if (active.volume < vol * 0.85) {
            await active.setVolume(vol);
          }
        }
      } catch (_) {}
      try {
        await inactive.setVolume(0.0);
      } catch (_) {}
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      await ResonateDiagnostics.recordDj(
        stage: 'engine_recover',
        outcome: 'applied',
        reason: reason,
        extra: {
          'activeVolume': active.volume,
          'activePlaying': active.playing,
          'userWantsPlaying': _userWantsPlaying,
          'activeEngine': _activeIsA ? 'A' : 'B',
          'preamp': vol,
        },
      );
    } catch (e) {
      debugPrint('DJ engine recover failed: $e');
    }
  }"""

if "userWantsPlaying': _userWantsPlaying" not in mp and "'userWantsPlaying': _userWantsPlaying" not in mp:
    if old_rec not in mp:
        print("WARN recover block miss - trying partial")
    else:
        mp = mp.replace(old_rec, new_rec, 1)
        print("recover strengthened")
else:
    print("recover already strong")

# ---------- Crossfade finally: always restore SFX + volume safety ----------
old_finally = """    } finally {
      _crossfadeInProgress = false;
      notifyListeners();

      // Critical fix: if the outgoing track reached completed while we were
      // crossfading, the normal completion path was suppressed. Force
      // continuation now that the hand-off is finished.
      if (_completionObservedDuringCrossfade) {
        _completionObservedDuringCrossfade = false;
        if (!_completionAdvanceInProgress) {
          unawaited(_ensureContinueAfterCrossfade());
        }
      } else {
        _completionObservedDuringCrossfade = false;
      }
    }
  }"""

new_finally = """    } finally {
      _crossfadeInProgress = false;
      // Always clear stretch + SFX even when the try path returned early.
      try {
        await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
      } catch (_) {}
      try {
        await _restoreDjTransitionSfx();
      } catch (_) {}
      // If UI thinks we are playing but active engine is near-silent, unstick.
      try {
        final active = audioPlayer;
        final vol = _eqPreampScale.clamp(0.05, 1.0).toDouble();
        if ((_userWantsPlaying || active.playing) && active.volume < 0.05) {
          await active.setSpeed(1.0);
          await active.setVolume(vol);
          await ResonateDiagnostics.record('playback_volume_unstick', {
            'reason': 'crossfade_finally',
            'volume': active.volume,
            'engine': _activeIsA ? 'A' : 'B',
          });
        }
      } catch (_) {}
      notifyListeners();

      // Critical fix: if the outgoing track reached completed while we were
      // crossfading, the normal completion path was suppressed. Force
      // continuation now that the hand-off is finished.
      if (_completionObservedDuringCrossfade) {
        _completionObservedDuringCrossfade = false;
        if (!_completionAdvanceInProgress) {
          unawaited(_ensureContinueAfterCrossfade());
        }
      } else {
        _completionObservedDuringCrossfade = false;
      }
    }
  }"""

if "playback_volume_unstick" not in mp:
    if old_finally not in mp:
        print("WARN finally miss")
    else:
        mp = mp.replace(old_finally, new_finally, 1)
        print("finally unstick")
else:
    print("finally already")

# ---------- After successful crossfade commit, explicit volume verify ----------
# Look for engine swap + isPlaying = true pattern
needle = "_activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active"
if needle in mp and "crossfade_commit_volume" not in mp:
    # Insert volume verify shortly after setVolume(master) on incoming
    old_commit = """      try { await incoming.setVolume(master); } catch (_) {}
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      try {
        if (incoming.volume < 0.05) await incoming.setVolume(master);
      } catch (_) {}
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active"""
    new_commit = """      try { await incoming.setVolume(master); } catch (_) {}
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      try {
        if (incoming.volume < 0.05) await incoming.setVolume(master);
      } catch (_) {}
      // Hard guarantee: incoming must be audible before we flip active engine.
      try {
        await incoming.setSpeed(1.0);
        await incoming.setVolume(master);
        if (!incoming.playing) {
          try { incoming.play(); } catch (_) {}
        }
        await ResonateDiagnostics.record('crossfade_commit_volume', {
          'volume': incoming.volume,
          'playing': incoming.playing,
          'master': master,
          'songId': nextSong.id,
        });
      } catch (_) {}
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active"""
    if old_commit in mp:
        mp = mp.replace(old_commit, new_commit, 1)
        print("commit volume guarantee")
    else:
        print("WARN commit block miss")

# ---------- playSongInternal: recover speed/volume after source load ----------
if "setVolume', target.setVolume(_eqPreampScale)" in mp or "setVolume', target.setVolume(_eqPreampScale)" in mp:
    pass
# After setVolume on play, ensure speed 1.0
old_vol = "await timed('setVolume', target.setVolume(_eqPreampScale), ms: 2000);"
new_vol = """await timed('setVolume', target.setVolume(_eqPreampScale.clamp(0.05, 1.0)), ms: 2000);
      try { await target.setSpeed(1.0); } catch (_) {}"""
if "target.setSpeed(1.0)" not in mp.split("setVolume', target.setVolume")[1][:120] if "setVolume', target.setVolume" in mp else True:
    if old_vol in mp:
        mp = mp.replace(old_vol, new_vol, 1)
        print("play speed reset")
    else:
        # alternate spacing
        old_vol2 = "await timed('setVolume', target.setVolume(_eqPreampScale), ms: 2000);"
        if old_vol2 in mp:
            mp = mp.replace(old_vol2, new_vol, 1)
            print("play speed reset2")

# ---------- resumePlayback: unstick if silent ----------
if "Future<void> resumePlayback" in mp and "recoverDjEngineState(reason: 'resume')" not in mp:
    # Find resumePlayback body - soft insert at start of internal
    import re
    m = re.search(r"Future<void> resumePlayback\([^)]*\)[^{]*\{", mp)
    if m:
        # Find next line after opening - inject recover call in the serialized play path
        # Safer: after isPlaying = true on resume
        pass
    # Hook: when position updates and playing with near-zero volume, recover once
    # Add method + call from position subscription if simple enough

# Position-based silent watchdog (throttled)
if "_lastSilentRecoverAt" not in mp:
    mp = mp.replace(
        "  DateTime? _lastPlayKickAt;",
        "  DateTime? _lastPlayKickAt;\n  DateTime? _lastSilentRecoverAt;",
        1,
    )
    watchdog = '''
  /// If UI says playing but engine volume is near zero outside a crossfade, unstick.
  void _maybeRecoverSilentPlayback() {
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    if (!_userWantsPlaying) return;
    try {
      final active = audioPlayer;
      if (!active.playing) return;
      if (active.volume >= 0.05) return;
      final now = DateTime.now();
      if (_lastSilentRecoverAt != null &&
          now.difference(_lastSilentRecoverAt!) < const Duration(seconds: 3)) {
        return;
      }
      _lastSilentRecoverAt = now;
      unawaited(_recoverDjEngineState(reason: 'silent_watchdog'));
    } catch (_) {}
  }
'''
    # insert before recover method
    if "Future<void> _recoverDjEngineState" in mp:
        mp = mp.replace(
            "  /// Restore normal speed + audible volume",
            watchdog + "  /// Restore normal speed + audible volume",
            1,
        )
        print("silent watchdog method")
    # Call from position stream handler
    if "currentPosition = position;" in mp and "_maybeRecoverSilentPlayback" not in mp:
        mp = mp.replace(
            "currentPosition = position;",
            "currentPosition = position;\n      _maybeRecoverSilentPlayback();",
            1,
        )
        print("silent watchdog hooked")

MP.write_text(mp)
print("DONE silent harden")
