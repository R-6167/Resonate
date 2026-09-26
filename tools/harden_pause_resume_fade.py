#!/usr/bin/env python3
"""Step 2 — soft fade on user pause / resume."""
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
    try_replace(
        MUSIC,
        """  static const double _duckLevel = 0.32;
  static const int _duckFadeMs = 180;
  static const Duration _autoResumeMaxFocusLoss = Duration(minutes: 3);""",
        """  static const double _duckLevel = 0.32;
  static const int _duckFadeMs = 180;
  /// Short transport fade for user pause / resume (keeps next/seek snappy).
  static const int _transportFadeMs = 220;
  static const Duration _autoResumeMaxFocusLoss = Duration(minutes: 3);""",
        'transport_fade_const',
    )

    try_replace(
        MUSIC,
        """  Future<void> pause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    // System audio-focus pause must preserve intent so we can resume when focus returns.
    final fromSystemFocus = source == 'system';
    if (!fromSystemFocus) {
      _cancelAutomaticPlaybackWork();
    }
    return _serializePlayback(() async {
      try {
        if (!fromSystemFocus) {
          _userWantsPlaying = false;
        }
        await audioPlayer.pause();
        // Quiet the inactive engine too so we do not keep mixing under another app.
        try {
          await inactivePlayer.pause();
        } catch (_) {}
        isPlaying = false;
        _persistResumePosition(force: true);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('audio_focus_pause', {
          'source': source,
          'userWantsPlaying': _userWantsPlaying,
          'preservedIntent': fromSystemFocus,
        });
      } catch (_) {}
    }, command: 'pause', source: source, userInitiated: !fromSystemFocus, intentToken: intentToken);
  }""",
        """  Future<void> pause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    // System audio-focus pause must preserve intent so we can resume when focus returns.
    final fromSystemFocus = source == 'system';
    final fromNoisy = source == 'becoming_noisy';
    if (!fromSystemFocus) {
      _cancelAutomaticPlaybackWork();
    }
    return _serializePlayback(() async {
      try {
        if (!fromSystemFocus) {
          _userWantsPlaying = false;
        }
        final midTransition =
            _crossfadeInProgress || _automaticCrossfadeInFlight;
        // Soft fade-out for user (and short system) pause — skip mid-crossfade.
        if (!midTransition && audioPlayer.playing) {
          final from = audioPlayer.volume;
          final fadeMs = fromSystemFocus ? 120 : _transportFadeMs;
          await _fadePlayerVolume(audioPlayer, from, 0.0, durationMs: fadeMs);
        }
        await audioPlayer.pause();
        try {
          await inactivePlayer.pause();
        } catch (_) {}
        // Restore internal gain so the next play/resume fade-in starts clean.
        if (!midTransition) {
          try {
            await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
          } catch (_) {}
        }
        isPlaying = false;
        _isDucked = false;
        _persistResumePosition(force: true);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('audio_focus_pause', {
          'source': source,
          'userWantsPlaying': _userWantsPlaying,
          'preservedIntent': fromSystemFocus,
          'faded': !midTransition,
          'noisy': fromNoisy,
        });
      } catch (_) {}
    }, command: 'pause', source: source, userInitiated: !fromSystemFocus, intentToken: intentToken);
  }""",
        'pause_fade_out',
    )

    try_replace(
        MUSIC,
        """  Future<void> resumePlayback({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      try {
        _userWantsPlaying = true;
        if (audioPlayer.audioSource != null) {
          try {
            final session = await AudioSession.instance;
            await session.setActive(true);
          } catch (_) {}
          // If we are sitting on a completed source, seek to zero first.
          if (audioPlayer.processingState == ProcessingState.completed) {
            try {
              await audioPlayer.seek(Duration.zero);
            } catch (_) {}
          }
          for (var attempt = 0; attempt < 12; attempt++) {
            if (attempt == 0 || attempt == 3 || attempt == 6) {
              try {
                audioPlayer.play();
              } catch (e) {
                debugPrint('resumePlayback play() fire $attempt failed: $e');
              }
            }
            if (audioPlayer.playing) break;
            await Future<void>.delayed(Duration(milliseconds: 40 + attempt * 25));
          }
          isPlaying = audioPlayer.playing || _userWantsPlaying;
          _publishServiceState();
          notifyListeners();
          return;
        }
        if (currentSong != null) {
          await _playSongInternal(
            currentSong!,
            queue: _queue.isEmpty ? null : _queue,
            startIndex: _queueIndex,
            resume: true,
            playbackIntentToken: intentToken,
          );
        }
      } catch (e) {
        debugPrint('resumePlayback failed: $e');
      }
    }, command: 'play', source: source, userInitiated: true, intentToken: intentToken);
  }""",
        """  Future<void> resumePlayback({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      try {
        _userWantsPlaying = true;
        _isDucked = false;
        if (audioPlayer.audioSource != null) {
          try {
            final session = await AudioSession.instance;
            await session.setActive(true);
          } catch (_) {}
          // If we are sitting on a completed source, seek to zero first.
          if (audioPlayer.processingState == ProcessingState.completed) {
            try {
              await audioPlayer.seek(Duration.zero);
            } catch (_) {}
          }
          final midTransition =
              _crossfadeInProgress || _automaticCrossfadeInFlight;
          final target = _eqPreampScale.clamp(0.0, 1.0);
          // Start quiet then fade in (skip mid-crossfade — ramp owns volume).
          if (!midTransition) {
            try {
              await audioPlayer.setVolume(0.0);
            } catch (_) {}
          }
          for (var attempt = 0; attempt < 12; attempt++) {
            if (attempt == 0 || attempt == 3 || attempt == 6) {
              try {
                audioPlayer.play();
              } catch (e) {
                debugPrint('resumePlayback play() fire $attempt failed: $e');
              }
            }
            if (audioPlayer.playing) break;
            await Future<void>.delayed(Duration(milliseconds: 40 + attempt * 25));
          }
          if (!midTransition && audioPlayer.playing) {
            await _fadePlayerVolume(
              audioPlayer,
              0.0,
              target,
              durationMs: source == 'system' ? 160 : _transportFadeMs,
            );
          } else if (!midTransition) {
            try {
              await audioPlayer.setVolume(target);
            } catch (_) {}
          }
          isPlaying = audioPlayer.playing || _userWantsPlaying;
          _publishServiceState();
          notifyListeners();
          unawaited(ResonateDiagnostics.record('playback_resume_fade', {
            'source': source,
            'faded': !midTransition,
            'playing': audioPlayer.playing,
          }));
          return;
        }
        if (currentSong != null) {
          await _playSongInternal(
            currentSong!,
            queue: _queue.isEmpty ? null : _queue,
            startIndex: _queueIndex,
            resume: true,
            playbackIntentToken: intentToken,
          );
        }
      } catch (e) {
        debugPrint('resumePlayback failed: $e');
      }
    }, command: 'play', source: source, userInitiated: source != 'system', intentToken: intentToken);
  }""",
        'resume_fade_in',
    )

    print('pause/resume fade done')


if __name__ == '__main__':
    main()
