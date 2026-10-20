#!/usr/bin/env python3
"""Restore music_provider.dart if corrupted, then apply audio-focus harden edits."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "lib/providers/music_provider.dart"
GOOD_SHAS = [
    "HEAD~1",
    "8551fb84ca3c42782edc332352bb80523b3255be",
]

OLD_CONFIGURE = """  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin && event.type == AudioInterruptionType.pause) unawaited(pause(source: 'system'));
        if (event.begin && event.type == AudioInterruptionType.duck) unawaited(_duckForInterruption());
        if (!event.begin && event.type == AudioInterruptionType.duck && isPlaying) unawaited(setVolume(_volume));
      });
      _noisySubscription = session.becomingNoisyEventStream.listen((_) { if (isPlaying) unawaited(pause(source: 'system')); });
    } catch (e) { debugPrint('Audio session setup failed: $e'); }
  }

  Future<void> _duckForInterruption() async { try { await audioPlayer.setVolume(.35); } catch (_) {} }
"""

NEW_CONFIGURE = """  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      // Explicit media focus (same base as .music()): exclusive GAIN so other apps
      // should not mix with us. We soft-duck on duck events; pause+resume on full pause.
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
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
      });
      _noisySubscription = session.becomingNoisyEventStream.listen((_) {
        // Headphones unplugged: treat as user-facing pause (do not auto-resume).
        if (isPlaying || _userWantsPlaying) {
          unawaited(pause(source: 'becoming_noisy'));
        }
      });
    } catch (e) {
      debugPrint('Audio session setup failed: $e');
    }
  }

  /// Soft-duck both engines so crossfade overlap does not leave one at full level.
  Future<void> _duckForInterruption() async {
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
  }
"""

OLD_PAUSE = """  Future<void> pause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      try {
        _userWantsPlaying = false;
        await audioPlayer.pause();
        isPlaying = false;
        _persistResumePosition(force: true);
        _publishServiceState();
        notifyListeners();
      } catch (_) {}
    }, command: 'pause', source: source, userInitiated: true, intentToken: intentToken);
  }
"""

NEW_PAUSE = """  Future<void> pause({String source = 'normal_player'}) {
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
  }
"""

OLD_STOP = """  Future<void> stop({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      if (!_playbackIntentGate.isCurrent(intentToken)) return;
      await _finishHistoryEvent();
      await _stopBoth();
      isPlaying = false;
      currentPosition = Duration.zero;
      _publishServiceState();
      notifyListeners();
    }, command: 'stop', source: source, userInitiated: true, intentToken: intentToken);
  }
"""

NEW_STOP = """  Future<void> stop({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      if (!_playbackIntentGate.isCurrent(intentToken)) return;
      _userWantsPlaying = false;
      await _finishHistoryEvent();
      await _stopBoth();
      isPlaying = false;
      currentPosition = Duration.zero;
      // Abandon audio focus so other apps can play without mixing with us.
      try {
        final session = await AudioSession.instance;
        await session.setActive(false);
      } catch (e) {
        debugPrint('AudioSession setActive(false) on stop failed: $e');
      }
      _publishServiceState();
      notifyListeners();
      await ResonateDiagnostics.record('audio_focus_stop', {'source': source});
    }, command: 'stop', source: source, userInitiated: true, intentToken: intentToken);
  }
"""

OLD_KICK = """          unawaited(() async {
            try {
              final session = await AudioSession.instance;
              await session.setActive(true);
            } catch (_) {}
            try {
              await player.seek(player.position);
            } catch (_) {}
            try {
              await player.play();
            } catch (_) {}
          }());"""

NEW_KICK = """          unawaited(() async {
            // Do not re-claim focus mid-crossfade — it can reset OEM volume/routing mid-ramp.
            if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
            try {
              final session = await AudioSession.instance;
              await session.setActive(true);
            } catch (_) {}
            try {
              await player.seek(player.position);
            } catch (_) {}
            try {
              await player.play();
            } catch (_) {}
          }());"""


def restore_from_git() -> bool:
    for ref in GOOD_SHAS:
        r = subprocess.run(
            ["git", "show", f"{ref}:lib/providers/music_provider.dart"],
            cwd=ROOT, capture_output=True, text=True,
        )
        if r.returncode == 0 and len(r.stdout) > 1000 and "MusicProvider" in r.stdout:
            TARGET.write_text(r.stdout)
            print(f"restored music_provider.dart from {ref} ({len(r.stdout)} bytes)")
            return True
        print(f"restore from {ref} failed: {(r.stderr or '')[:200]}")
    return False


def main() -> int:
    if not TARGET.exists():
        print("missing", TARGET)
        return 1
    text = TARGET.read_text()
    if "_unduckAfterInterruption" in text and "AndroidAudioFocusGainType.gain" in text:
        print("audio focus harden already present")
        return 0
    if "PLACEHOLDER" in text or len(text) < 1000:
        print("music_provider.dart looks corrupted; restoring…")
        if not restore_from_git():
            print("FATAL: could not restore base file")
            return 2
        text = TARGET.read_text()

    replacements = [
        ("configure", OLD_CONFIGURE, NEW_CONFIGURE),
        ("pause", OLD_PAUSE, NEW_PAUSE),
        ("stop", OLD_STOP, NEW_STOP),
        ("kick", OLD_KICK, NEW_KICK),
    ]
    for name, old, new in replacements:
        if old not in text:
            print(f"block not found: {name}")
            return 3
        text = text.replace(old, new, 1)
        print(f"replaced {name}")

    if "_unduckAfterInterruption" not in text:
        print("marker missing after edits")
        return 4
    TARGET.write_text(text)
    print("applied audio focus harden OK", TARGET.stat().st_size, "bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
