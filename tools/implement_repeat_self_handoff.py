#!/usr/bin/env python3
"""Step 3 — repeat-one + crossfade dual-engine self-handoff."""
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
    # State fields near other crossfade flags
    try_replace(
        MUSIC,
        """  bool _crossfadePreloadInFlight = false;
  /// DJ Mode Step 2 — only true when DjModeProvider master + beat-align are on.""",
        """  bool _crossfadePreloadInFlight = false;
  /// Repeat-one + crossfade: seamless loop via idle engine (no queue advance).
  bool _repeatSelfHandoffArmed = false;
  bool _repeatSelfHandoffInFlight = false;
  String? _repeatSelfTargetSongId;
  /// DJ Mode Step 2 — only true when DjModeProvider master + beat-align are on.""",
        'self_handoff_fields',
    )

    # Getter after canCrossfadeNext
    try_replace(
        MUSIC,
        """  bool get canCrossfadeNext {
    if (_crossfadeInProgress || _queue.isEmpty || _queueIndex < 0) return false;
    if (_repeatMode == PlaybackRepeatMode.one) return false;
    if (_queueIndex < _queue.length - 1) return true;
    if (_repeatMode == PlaybackRepeatMode.all && _queue.length > 1) return true;
    return false;
  }""",
        """  bool get canCrossfadeNext {
    if (_crossfadeInProgress || _queue.isEmpty || _queueIndex < 0) return false;
    if (_repeatMode == PlaybackRepeatMode.one) return false;
    if (_queueIndex < _queue.length - 1) return true;
    if (_repeatMode == PlaybackRepeatMode.all && _queue.length > 1) return true;
    return false;
  }

  /// Seamless loop: same song on the idle engine when repeat-one + crossfade.
  bool get canRepeatSelfHandoff {
    if (!_crossfadeEnabled) return false;
    if (_repeatMode != PlaybackRepeatMode.one) return false;
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _transportInFlight) {
      return false;
    }
    if (currentSong == null || currentSong!.filePath.trim().isEmpty) return false;
    if (!audioPlayer.playing && !_userWantsPlaying) return false;
    return true;
  }""",
        'can_repeat_self_handoff',
    )

    # Near-end watchdog: branch for self-handoff before playlist crossfade
    try_replace(
        MUSIC,
        """  void _maybeStartAutomaticCrossfade(Duration position) {
    if (!_crossfadeEnabled || !canCrossfadeNext || !audioPlayer.playing) return;
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    final duration = audioPlayer.duration ?? currentDuration;
    if (duration == null || duration <= Duration.zero) return;
    final remaining = duration - position;
    if (remaining <= Duration.zero) return;

    final preloadMs = (_crossfadeDurationMs + 10000).clamp(10000, 28000);
    final fadeArmMs = _crossfadeDurationMs + 2000;
    if (remaining <= Duration(milliseconds: preloadMs) &&
        remaining > Duration(milliseconds: fadeArmMs)) {
      unawaited(_preloadNextForCrossfade());
    }

    final startMarginMs = (1200 + (_crossfadeDurationMs ~/ 10)).clamp(1500, 3000);
    final triggerMs = (_crossfadeDurationMs + startMarginMs).clamp(2000, 16000);
    if (remaining > Duration(milliseconds: triggerMs)) return;
    if (remaining < const Duration(milliseconds: 1200)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());
  }""",
        """  void _maybeStartAutomaticCrossfade(Duration position) {
    if (!_crossfadeEnabled || !audioPlayer.playing) return;
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight) {
      return;
    }
    final duration = audioPlayer.duration ?? currentDuration;
    if (duration == null || duration <= Duration.zero) return;
    final remaining = duration - position;
    if (remaining <= Duration.zero) return;

    // Repeat-one seamless loop (dual-engine self-handoff).
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
    }

    if (!canCrossfadeNext) return;

    final preloadMs = (_crossfadeDurationMs + 10000).clamp(10000, 28000);
    final fadeArmMs = _crossfadeDurationMs + 2000;
    if (remaining <= Duration(milliseconds: preloadMs) &&
        remaining > Duration(milliseconds: fadeArmMs)) {
      unawaited(_preloadNextForCrossfade());
    }

    final startMarginMs = (1200 + (_crossfadeDurationMs ~/ 10)).clamp(1500, 3000);
    final triggerMs = (_crossfadeDurationMs + startMarginMs).clamp(2000, 16000);
    if (remaining > Duration(milliseconds: triggerMs)) return;
    if (remaining < const Duration(milliseconds: 1200)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());
  }""",
        'maybe_start_self_branch',
    )

    # Insert self-handoff methods before _preloadNextForCrossfade
    try_replace(
        MUSIC,
        """  Future<void> _preloadNextForCrossfade() async {
    if (!_crossfadeEnabled || _crossfadePreloadInFlight || !canCrossfadeNext) return;""",
        """  Future<void> _preloadRepeatSelf(Song song) async {
    if (_repeatSelfHandoffInFlight) return;
    final incoming = inactivePlayer;
    final incomingEq = inactiveEqualizer;
    final incomingLoud = inactiveLoudnessEnhancer;
    try {
      await ResonateDiagnostics.record('repeat_self_arm', {
        'songId': song.id,
        'positionMs': currentPosition.inMilliseconds,
        'xfMs': _crossfadeDurationMs,
      });
      try {
        await incoming.stop();
      } catch (_) {}
      await _loadSingle(incoming, incomingEq, incomingLoud, song, start: false);
      try {
        await incoming.seek(Duration.zero);
      } catch (_) {}
      try {
        await incoming.setVolume(0.0);
      } catch (_) {}
      _preloadedNextSongId = song.id;
    } catch (e) {
      debugPrint('repeat self preload failed: $e');
      _repeatSelfHandoffArmed = false;
      _repeatSelfTargetSongId = null;
      unawaited(ResonateDiagnostics.record('repeat_self_cancel', {
        'reason': 'preload_fail',
        'error': '$e',
      }));
    }
  }

  Future<void> _runRepeatSelfHandoff() async {
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
  }

  Future<bool> _performRepeatSelfHandoff({
    required int milliseconds,
    String fadeType = 'linear',
  }) async {
    final song = currentSong;
    if (song == null || song.filePath.trim().isEmpty) return false;
    if (!audioPlayer.playing && !_userWantsPlaying) return false;
    _repeatSelfHandoffInFlight = true;
    _crossfadeInProgress = true;
    final outgoing = audioPlayer;
    final incoming = inactivePlayer;
    final incomingEq = inactiveEqualizer;
    final incomingLoud = inactiveLoudnessEnhancer;
    final master = _eqPreampScale.clamp(0.05, 1.0);
    final ms = milliseconds.clamp(500, 12000);
    try {
      // No DJ stretch / SFX on self-loop — pure volume blend.
      try {
        await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      } catch (_) {}
      try {
        await outgoing.setLoopMode(LoopMode.off);
      } catch (_) {}

      final already = _preloadedNextSongId == song.id;
      if (!already) {
        try {
          await incoming.stop();
        } catch (_) {}
        await _loadSingle(incoming, incomingEq, incomingLoud, song, start: false);
      }
      try {
        await incoming.seek(Duration.zero);
      } catch (_) {}
      await incoming.setVolume(0.0);

      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}

      try {
        await incoming.play();
      } catch (_) {}

      unawaited(ResonateDiagnostics.record('repeat_self_ramp', {
        'songId': song.id,
        'fromEngine': _activeIsA ? 'A' : 'B',
        'toEngine': _activeIsA ? 'B' : 'A',
        'ms': ms,
      }));

      final steps = (ms / 40).round().clamp(8, 80);
      final stepMs = (ms / steps).round().clamp(20, 80);
      for (var i = 1; i <= steps; i++) {
        if (!_repeatSelfHandoffInFlight || !_userWantsPlaying) {
          // Cancelled mid-ramp.
          try {
            await incoming.pause();
          } catch (_) {}
          try {
            await incoming.setVolume(0.0);
          } catch (_) {}
          try {
            await outgoing.setVolume(master);
          } catch (_) {}
          return false;
        }
        final t = i / steps;
        double outV;
        double inV;
        switch (fadeType) {
          case 'ease_in':
            outV = master * (1.0 - t * t);
            inV = master * (t * t);
            break;
          case 'ease_out':
            final u = 1.0 - t;
            outV = master * (u * u);
            inV = master * (1.0 - u * u);
            break;
          case 'ease_in_out':
            final s = t * t * (3.0 - 2.0 * t);
            outV = master * (1.0 - s);
            inV = master * s;
            break;
          default:
            outV = master * (1.0 - t);
            inV = master * t;
        }
        try {
          await outgoing.setVolume(outV.clamp(0.0, 1.0));
        } catch (_) {}
        try {
          await incoming.setVolume(inV.clamp(0.0, 1.0));
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }

      // Commit: swap engines, same song + index.
      _activeIsA = !_activeIsA;
      _lastCompletionSongId = null;
      currentPosition = incoming.position;
      currentDuration = song.duration;
      isPlaying = incoming.playing || _userWantsPlaying;
      _bindActivePlayerStreams();
      _publishServiceState();
      notifyListeners();

      try {
        await outgoing.pause();
      } catch (_) {}
      try {
        await outgoing.setVolume(master);
      } catch (_) {}
      try {
        await incoming.setVolume(master);
      } catch (_) {}
      _preloadedNextSongId = null;

      await ResonateDiagnostics.record('repeat_self_committed', {
        'songId': song.id,
        'activeEngine': _activeIsA ? 'A' : 'B',
        'queueIndex': _queueIndex,
      });
      return true;
    } catch (e, st) {
      debugPrint('repeat self handoff failed: $e\n$st');
      try {
        await incoming.pause();
      } catch (_) {}
      try {
        await outgoing.setVolume(master);
      } catch (_) {}
      return false;
    } finally {
      _crossfadeInProgress = false;
      _repeatSelfHandoffInFlight = false;
      _repeatSelfHandoffArmed = false;
      _repeatSelfTargetSongId = null;
    }
  }

  Future<void> _preloadNextForCrossfade() async {
    if (!_crossfadeEnabled || _crossfadePreloadInFlight || !canCrossfadeNext) return;""",
        'self_handoff_methods',
    )

    # Cancel self-handoff in _cancelAutomaticPlaybackWork
    try_replace(
        MUSIC,
        """  void _cancelAutomaticPlaybackWork() {
    _automaticCrossfadeInFlight = false;
    _crossfadeInProgress = false;
    _completionAdvanceInProgress = false;
    _completionObservedDuringCrossfade = false;
    _preloadedNextSongId = null;
    _crossfadePreloadInFlight = false;""",
        """  void _cancelAutomaticPlaybackWork() {
    _automaticCrossfadeInFlight = false;
    _crossfadeInProgress = false;
    _completionAdvanceInProgress = false;
    _completionObservedDuringCrossfade = false;
    _preloadedNextSongId = null;
    _crossfadePreloadInFlight = false;
    if (_repeatSelfHandoffArmed || _repeatSelfHandoffInFlight) {
      unawaited(ResonateDiagnostics.record('repeat_self_cancel', {
        'reason': 'transport_cancel',
        'songId': _repeatSelfTargetSongId,
      }));
    }
    _repeatSelfHandoffArmed = false;
    _repeatSelfHandoffInFlight = false;
    _repeatSelfTargetSongId = null;""",
        'cancel_self_handoff',
    )

    # Completion: if self-handoff in flight, ignore hard repeat seek
    try_replace(
        MUSIC,
        """      if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
        _lastCompletionSongId = null;
        currentPosition = Duration.zero;
        await audioPlayer.seek(Duration.zero);
        await audioPlayer.play();
        isPlaying = true;
        await _startHistoryEvent(currentSong!);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('completion_advance_result', {'result': 'repeated', 'songId': currentSong?.id});
        return;
      }""",
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
        'completion_repeat_guard',
    )

    print('repeat self handoff implement done')


if __name__ == '__main__':
    main()
