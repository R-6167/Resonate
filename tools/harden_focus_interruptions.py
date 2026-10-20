#!/usr/bin/env python3
"""Step 1 — audio focus + interruption reliability (fade duck, resume, diagnostics)."""
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
    # --- State fields after _lastRouteRecoverAt ---
    try_replace(
        MUSIC,
        """  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSubscription;
  DateTime? _lastRouteRecoverAt;

  ListeningEvent? _activeHistoryEvent;""",
        """  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSubscription;
  DateTime? _lastRouteRecoverAt;

  /// True while system asked us to duck (notification / nav / transient).
  bool _isDucked = false;
  /// When exclusive focus was lost (call / other media) — used for long-call gate.
  DateTime? _focusLostAt;
  int _volumeFadeGen = 0;
  static const double _duckLevel = 0.32;
  static const int _duckFadeMs = 180;
  static const Duration _autoResumeMaxFocusLoss = Duration(minutes: 3);

  ListeningEvent? _activeHistoryEvent;""",
        'focus_state_fields',
    )

    # --- Replace session interruption listener with logged + long-call aware version ---
    try_replace(
        MUSIC,
        """      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          if (event.type == AudioInterruptionType.pause) {
            // System took exclusive focus (call, other media). Keep user intent so we can resume.
            unawaited(pause(source: 'system'));
          } else if (event.type == AudioInterruptionType.duck) {
            unawaited(_duckForInterruption());
          }
        } else {
          // Interruption ended — restore if the user still wants playback.
          if (event.type == AudioInterruptionType.duck) {
            if (_userWantsPlaying) unawaited(_unduckAfterInterruption());
          } else if (event.type == AudioInterruptionType.pause) {
            if (_userWantsPlaying) {
              unawaited(resumePlayback(source: 'system'));
            }
          }
        }
      });""",
        """      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        unawaited(ResonateDiagnostics.record('audio_focus_event', {
          'begin': event.begin,
          'type': event.type.name,
          'userWantsPlaying': _userWantsPlaying,
          'isPlaying': isPlaying,
          'isDucked': _isDucked,
          'songId': currentSong?.id,
        }));
        if (event.begin) {
          if (event.type == AudioInterruptionType.pause) {
            // Calls / exclusive media: pause, keep intent, stamp focus-loss time.
            _focusLostAt = DateTime.now();
            unawaited(pause(source: 'system'));
          } else if (event.type == AudioInterruptionType.duck) {
            // Notifications / nav / transient: soft duck with fade.
            unawaited(_duckForInterruption());
          } else {
            // Unknown transient — prefer duck over a hard stop.
            unawaited(_duckForInterruption());
          }
        } else {
          if (event.type == AudioInterruptionType.duck) {
            if (_userWantsPlaying) unawaited(_unduckAfterInterruption());
          } else if (event.type == AudioInterruptionType.pause) {
            final lostAt = _focusLostAt;
            _focusLostAt = null;
            final lostLong = lostAt != null &&
                DateTime.now().difference(lostAt) > _autoResumeMaxFocusLoss;
            if (lostLong) {
              // Long call: do not surprise-resume; user taps play when ready.
              _userWantsPlaying = false;
              unawaited(ResonateDiagnostics.record('audio_focus_event', {
                'action': 'skip_auto_resume_long_focus_loss',
                'lostMs': lostAt == null
                    ? null
                    : DateTime.now().difference(lostAt).inMilliseconds,
              }));
              return;
            }
            if (_userWantsPlaying) {
              unawaited(_resumeAfterSystemFocus());
            }
          } else if (_userWantsPlaying && _isDucked) {
            unawaited(_unduckAfterInterruption());
          }
        }
      });""",
        'interruption_listener',
    )

    # --- Fade-based duck / unduck ---
    try_replace(
        MUSIC,
        """  Future<void> _duckForInterruption() async {
    final ducked = (0.35 * _eqPreampScale).clamp(0.0, 1.0);
    try {
      await Future.wait([
        _playerA.setVolume(ducked),
        _playerB.setVolume(ducked),
      ]);
    } catch (_) {
      try {
        await audioPlayer.setVolume(ducked);
      } catch (_) {}
    }
  }

  Future<void> _unduckAfterInterruption() async {
    final restored = _eqPreampScale.clamp(0.0, 1.0);
    try {
      // Restore active engine to full internal gain; keep inactive quiet unless mid-crossfade.
      if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
        // Mid-fade: leave volumes to the crossfade loop.
        return;
      }
      await audioPlayer.setVolume(restored);
      try {
        await inactivePlayer.setVolume(0.0);
      } catch (_) {}
    } catch (_) {
      try {
        await setVolume(_volume);
      } catch (_) {}
    }
  }""",
        """  Future<void> _fadePlayerVolume(
    AudioPlayer player,
    double from,
    double to, {
    int durationMs = _duckFadeMs,
    int steps = 6,
  }) async {
    final gen = ++_volumeFadeGen;
    final start = from.clamp(0.0, 1.0);
    final end = to.clamp(0.0, 1.0);
    if ((start - end).abs() < 0.01) {
      try {
        await player.setVolume(end);
      } catch (_) {}
      return;
    }
    final stepMs = (durationMs / steps).round().clamp(16, 80);
    for (var i = 1; i <= steps; i++) {
      if (gen != _volumeFadeGen) return; // superseded by newer fade / transport
      if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
      final t = i / steps;
      final v = start + (end - start) * t;
      try {
        await player.setVolume(v.clamp(0.0, 1.0));
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: stepMs));
    }
  }

  Future<void> _duckForInterruption() async {
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
      // Let the crossfade own volumes; mark ducked so we restore after.
      _isDucked = true;
      return;
    }
    _isDucked = true;
    final target = (_duckLevel * _eqPreampScale).clamp(0.05, 0.45);
    try {
      final aVol = _playerA.volume;
      final bVol = _playerB.volume;
      // Fade active; keep inactive quiet.
      if (_activeIsA) {
        await _fadePlayerVolume(_playerA, aVol, target);
        try {
          await _playerB.setVolume(0.0);
        } catch (_) {}
      } else {
        await _fadePlayerVolume(_playerB, bVol, target);
        try {
          await _playerA.setVolume(0.0);
        } catch (_) {}
      }
      unawaited(ResonateDiagnostics.record('audio_focus_duck', {
        'level': target,
        'engine': _activeIsA ? 'A' : 'B',
      }));
    } catch (_) {
      try {
        await audioPlayer.setVolume(target);
      } catch (_) {}
    }
  }

  Future<void> _unduckAfterInterruption() async {
    if (!_isDucked && audioPlayer.volume >= _eqPreampScale * 0.9) {
      return;
    }
    try {
      if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
        _isDucked = false;
        return;
      }
      final restored = _eqPreampScale.clamp(0.0, 1.0);
      final from = audioPlayer.volume;
      await _fadePlayerVolume(audioPlayer, from, restored);
      try {
        await inactivePlayer.setVolume(0.0);
      } catch (_) {}
      _isDucked = false;
      unawaited(ResonateDiagnostics.record('audio_focus_unduck', {
        'level': restored,
        'engine': _activeIsA ? 'A' : 'B',
      }));
    } catch (_) {
      _isDucked = false;
      try {
        await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
      } catch (_) {}
    }
  }

  /// Re-claim session then resume after a call / exclusive focus loss.
  Future<void> _resumeAfterSystemFocus() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
    // Brief settle for OEM audio policy after a call.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!_userWantsPlaying) return;
    _isDucked = false;
    try {
      await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
    } catch (_) {}
    await resumePlayback(source: 'system');
    // Nudge volume again — some devices stay muted one tick after setActive.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_userWantsPlaying && !_crossfadeInProgress) {
      try {
        await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
        if (!audioPlayer.playing) {
          try {
            audioPlayer.play();
          } catch (_) {}
        }
      } catch (_) {}
    }
  }""",
        'duck_unduck_fade',
    )

    # --- System resume path: when interruption ends we call _resumeAfterSystemFocus;
    # ensure resumePlayback from system does not treat as user cancel of everything
    # (already fine). Bump diagnostics on system resume via source.

    print('focus interruption harden done')


if __name__ == '__main__':
    main()
