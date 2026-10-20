#!/usr/bin/env python3
"""Harden repeat-one (soft single-engine loop), stuck-crossfade watchdog, static."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / 'lib/providers/music_provider.dart'


def try_replace(path: Path, old: str, new: str, label: str) -> bool:
    t = path.read_text()
    if old not in t:
        print('skip', label)
        return False
    path.write_text(t.replace(old, new, 1))
    print('ok', label)
    return True


def main() -> None:
    # --- Near-end: use soft single-engine loop (no dual same-URI load) ---
    try_replace(
        MUSIC,
        """    // Repeat-one seamless loop (dual-engine self-handoff).
    if (_repeatMode == PlaybackRepeatMode.one) {
      if (!canRepeatSelfHandoff) return;
      final armMs = (_crossfadeDurationMs + 2500).clamp(2500, 12000);
      final triggerMs = (_crossfadeDurationMs + 1500).clamp(2000, 10000);
      final song = currentSong;
      if (song == null) return;
      if (remaining <= Duration(milliseconds: armMs) &&
          remaining > Duration(milliseconds: triggerMs) &&
          !_repeatSelfHandoffArmed) {
        _repeatSelfHandoffArmed = true;
        _repeatSelfTargetSongId = song.id;
        unawaited(_preloadRepeatSelf(song));
      }
      if (remaining > Duration(milliseconds: triggerMs)) return;
      if (remaining < const Duration(milliseconds: 900)) return;
      _automaticCrossfadeInFlight = true;
      unawaited(_runRepeatSelfHandoff());
      return;
    }""",
        """    // Repeat-one: soft single-engine loop (same MediaStore URI on two
    // engines hangs on many OEMs — dual path removed for reliability).
    if (_repeatMode == PlaybackRepeatMode.one) {
      if (!_crossfadeEnabled || _repeatSelfHandoffInFlight || _transportInFlight) {
        return;
      }
      if (currentSong == null) return;
      // Short loop fade: long dual fades were arming late and never committing.
      final loopMs = _crossfadeDurationMs.clamp(800, 3500);
      final triggerMs = (loopMs + 400).clamp(1200, 4000);
      if (remaining > Duration(milliseconds: triggerMs)) return;
      if (remaining < const Duration(milliseconds: 250)) return;
      _repeatSelfHandoffInFlight = true;
      _automaticCrossfadeInFlight = true;
      unawaited(_runRepeatSelfSoftLoop(loopMs: loopMs));
      return;
    }""",
        'repeat_trigger_soft',
    )

    # --- Replace run/perform dual path with soft loop runner (insert before old preload) ---
    # Keep old methods but add soft loop that is actually called; simplify _runRepeatSelfHandoff
    try_replace(
        MUSIC,
        """  Future<void> _runRepeatSelfHandoff() async {
    final song = currentSong;
    final targetId = _repeatSelfTargetSongId ?? song?.id;
    if (song == null || targetId == null || song.id != targetId) {
      _automaticCrossfadeInFlight = false;
      _repeatSelfHandoffArmed = false;
      return;
    }
    final ok = await _performRepeatSelfHandoff(
      milliseconds: _crossfadeDurationMs,
      fadeType: _crossfadeFadeType,
    );
    _automaticCrossfadeInFlight = false;
    _repeatSelfHandoffArmed = false;
    _repeatSelfHandoffInFlight = false;
    _repeatSelfTargetSongId = null;
    if (!ok) {
      // Fallback: classic seek-to-start on the active engine.
      try {
        await audioPlayer.seek(Duration.zero);
        if (_userWantsPlaying) await audioPlayer.play();
      } catch (_) {}
      unawaited(ResonateDiagnostics.record('repeat_self_fallback', {
        'reason': 'handoff_failed',
        'songId': song.id,
      }));
    }
  }""",
        """  /// Soft loop: fade out → seek(0) → fade in on the *active* engine only.
  /// Avoids loading the same content:// URI on A and B (OEM hang / static).
  Future<void> _runRepeatSelfSoftLoop({required int loopMs}) async {
    final song = currentSong;
    if (song == null) {
      _automaticCrossfadeInFlight = false;
      _repeatSelfHandoffInFlight = false;
      return;
    }
    final ms = loopMs.clamp(600, 4000);
    final master = _eqPreampScale.clamp(0.05, 1.0);
    final player = audioPlayer;
    unawaited(ResonateDiagnostics.record('repeat_self_ramp', {
      'mode': 'soft_single',
      'songId': song.id,
      'ms': ms,
      'engine': _activeIsA ? 'A' : 'B',
    }));
    try {
      // Keep inactive fully quiet so nothing bleeds.
      try {
        await inactivePlayer.setVolume(0.0);
      } catch (_) {}
      try {
        await inactivePlayer.pause();
      } catch (_) {}

      final from = player.volume.clamp(0.0, 1.0);
      await _fadePlayerVolume(player, from, 0.0, durationMs: ms ~/ 2);
      if (!_userWantsPlaying) {
        unawaited(ResonateDiagnostics.record('repeat_self_cancel', {
          'reason': 'user_stopped',
          'songId': song.id,
        }));
        return;
      }
      try {
        await player.seek(Duration.zero);
      } catch (e) {
        debugPrint('soft loop seek: $e');
      }
      currentPosition = Duration.zero;
      try {
        player.play();
      } catch (_) {}
      for (var i = 0; i < 10 && !player.playing && _userWantsPlaying; i++) {
        await Future<void>.delayed(Duration(milliseconds: 30 + i * 20));
        try {
          player.play();
        } catch (_) {}
      }
      await _fadePlayerVolume(player, 0.0, master, durationMs: ms ~/ 2);
      isPlaying = player.playing || _userWantsPlaying;
      _lastCompletionSongId = null;
      _publishServiceState();
      notifyListeners();
      unawaited(ResonateDiagnostics.record('repeat_self_committed', {
        'mode': 'soft_single',
        'songId': song.id,
        'activeEngine': _activeIsA ? 'A' : 'B',
        'playing': player.playing,
      }));
    } catch (e, st) {
      debugPrint('soft loop failed: $e');
      debugPrint('$st');
      try {
        await player.seek(Duration.zero);
        if (_userWantsPlaying) {
          try {
            player.play();
          } catch (_) {}
          try {
            await player.setVolume(master);
          } catch (_) {}
        }
      } catch (_) {}
      unawaited(ResonateDiagnostics.record('repeat_self_fallback', {
        'reason': 'soft_loop_error',
        'songId': song.id,
        'error': '$e',
      }));
    } finally {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
      _repeatSelfHandoffInFlight = false;
      _repeatSelfHandoffArmed = false;
      _repeatSelfTargetSongId = null;
    }
  }

  Future<void> _runRepeatSelfHandoff() async {
    // Legacy entry — redirect to soft loop.
    final loopMs = _crossfadeDurationMs.clamp(800, 3500);
    await _runRepeatSelfSoftLoop(loopMs: loopMs);
  }""",
        'soft_loop_impl',
    )

    # --- Watchdog stuck: clear self-handoff + don't kill active engine ---
    try_replace(
        MUSIC,
        """      if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
        unawaited(ResonateDiagnostics.record('end_of_track_watchdog_crossfade_stuck', {
          'songId': currentSong?.id,
          'crossfadeInProgress': _crossfadeInProgress,
          'automaticCrossfadeInFlight': _automaticCrossfadeInFlight,
          'graceMs': graceMs,
        }));
        _crossfadeInProgress = false;
        _automaticCrossfadeInFlight = false;
        _completionObservedDuringCrossfade = false;
        // Silence B so a half-started fade cannot keep making static.
        unawaited(() async {
          try {
            await _playerB.stop();
          } catch (_) {}
          try {
            await _playerB.setVolume(0.0);
          } catch (_) {}
        }());
      }""",
        """      if (_crossfadeInProgress ||
          _automaticCrossfadeInFlight ||
          _repeatSelfHandoffInFlight) {
        unawaited(ResonateDiagnostics.record('end_of_track_watchdog_crossfade_stuck', {
          'songId': currentSong?.id,
          'crossfadeInProgress': _crossfadeInProgress,
          'automaticCrossfadeInFlight': _automaticCrossfadeInFlight,
          'repeatSelfInFlight': _repeatSelfHandoffInFlight,
          'graceMs': graceMs,
          'activeEngine': _activeIsA ? 'A' : 'B',
        }));
        _crossfadeInProgress = false;
        _automaticCrossfadeInFlight = false;
        _completionObservedDuringCrossfade = false;
        _repeatSelfHandoffInFlight = false;
        _repeatSelfHandoffArmed = false;
        _repeatSelfTargetSongId = null;
        // Silence *inactive* only — never stop the active engine (was killing B
        // after a crossfade commit when B was active → silence / static).
        unawaited(() async {
          try {
            await inactivePlayer.pause();
          } catch (_) {}
          try {
            await inactivePlayer.setVolume(0.0);
          } catch (_) {}
          try {
            await audioPlayer.setVolume(_eqPreampScale.clamp(0.05, 1.0));
          } catch (_) {}
        }());
      }""",
        'watchdog_stuck_safe',
    )

    # --- Completion: if deferred but not actually in flight, do hard repeat ---
    try_replace(
        MUSIC,
        """      if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
        // Dual-engine self-handoff owns the loop when crossfade is on.
        if (_repeatSelfHandoffInFlight ||
            _crossfadeInProgress ||
            (_crossfadeEnabled && _automaticCrossfadeInFlight)) {
          await ResonateDiagnostics.record('completion_advance_result', {
            'result': 'repeat_deferred_to_self_handoff',
            'songId': currentSong?.id,
          });
          return;
        }
        _lastCompletionSongId = null;
        currentPosition = Duration.zero;
        await audioPlayer.seek(Duration.zero);
        await audioPlayer.play();
        isPlaying = true;
        await _startHistoryEvent(currentSong!);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('completion_advance_result', {
          'result': 'repeated',
          'songId': currentSong?.id,
        });
        return;
      }""",
        """      if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
        // Only defer while soft-loop is *actually* running (not stuck flags).
        if (_repeatSelfHandoffInFlight) {
          await ResonateDiagnostics.record('completion_advance_result', {
            'result': 'repeat_deferred_to_self_handoff',
            'songId': currentSong?.id,
          });
          return;
        }
        _lastCompletionSongId = null;
        currentPosition = Duration.zero;
        try {
          await audioPlayer.setVolume(_eqPreampScale.clamp(0.05, 1.0));
        } catch (_) {}
        await audioPlayer.seek(Duration.zero);
        try {
          audioPlayer.play();
        } catch (_) {}
        isPlaying = true;
        _userWantsPlaying = true;
        await _startHistoryEvent(currentSong!);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('completion_advance_result', {
          'result': 'repeated',
          'songId': currentSong?.id,
        });
        return;
      }""",
        'completion_repeat_hard_fallback',
    )

    # --- Crossfade static: force inactive quiet before ramp starts in true crossfade ---
    # Look for setVolume(0) before play on incoming in _performTrueCrossfade
    try_replace(
        MUSIC,
        """      await incoming.setVolume(0.0);
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      await _prepareDjHandoff(
        outgoing: outgoing,
        incoming: incoming,
        outgoingSong: outgoingSong,
        incomingSong: nextSong,
      );""",
        """      await incoming.setVolume(0.0);
      // Hard-mute before play — prevents a one-frame blast / static on some OEMs.
      try {
        await outgoing.setVolume(outgoing.volume.clamp(0.0, 1.0));
      } catch (_) {}
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      await _prepareDjHandoff(
        outgoing: outgoing,
        incoming: incoming,
        outgoingSong: outgoingSong,
        incomingSong: nextSong,
      );""",
        'crossfade_pre_mute',
    )

    print('harden repeat/static done')


if __name__ == '__main__':
    main()
