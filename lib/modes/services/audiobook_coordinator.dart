import '../models/audiobook_intent.dart';
import '../models/resonate_mode.dart';

/// Deterministic Audiobook Mode coordinator.
///
/// It owns the audiobook session contract and resume/navigation signals only.
/// Playback, chapter metadata, position persistence, and sleep-timer execution
/// remain responsibilities of the host Resonate application.
class AudiobookCoordinator {
  ResonateMode _mode = ResonateMode.audiobook;
  bool _active = false;
  bool _paused = false;
  Duration? _lastKnownPosition;

  ResonateMode get mode => _mode;
  bool get isActive => _active;
  bool get isPaused => _paused;
  Duration? get lastKnownPosition => _lastKnownPosition;

  void setMode(ResonateMode mode) => _mode = mode;

  List<AudiobookIntent> start(DateTime now, {Duration? resumePosition}) {
    if (_active) return const [];

    _active = true;
    _paused = false;
    _lastKnownPosition = resumePosition;

    final intents = <AudiobookIntent>[
      AudiobookIntent(
        type: AudiobookIntentType.sessionStarted,
        at: now,
        mode: _mode,
      ),
      AudiobookIntent(
        type: AudiobookIntentType.speedControlsElevated,
        at: now,
        mode: _mode,
      ),
      AudiobookIntent(
        type: AudiobookIntentType.sleepTimerSuggested,
        at: now,
        mode: _mode,
      ),
      AudiobookIntent(
        type: AudiobookIntentType.chapterNavigationAvailable,
        at: now,
        mode: _mode,
      ),
    ];

    if (resumePosition != null) {
      intents.add(AudiobookIntent(
        type: AudiobookIntentType.resumePositionRequired,
        at: now,
        mode: _mode,
        position: resumePosition,
      ));
    }

    return intents;
  }

  List<AudiobookIntent> pause(DateTime now, {Duration? position}) {
    if (!_active || _paused) return const [];
    if (position != null) _setPosition(position);
    _paused = true;

    return [
      AudiobookIntent(
        type: AudiobookIntentType.sessionPaused,
        at: now,
        mode: _mode,
        position: _lastKnownPosition,
      ),
    ];
  }

  List<AudiobookIntent> resume(DateTime now, {Duration? position}) {
    if (!_active || !_paused) return const [];
    if (position != null) _setPosition(position);
    _paused = false;

    return [
      AudiobookIntent(
        type: AudiobookIntentType.sessionResumed,
        at: now,
        mode: _mode,
        position: _lastKnownPosition,
      ),
    ];
  }

  void updatePosition(Duration position) {
    if (!_active || position < Duration.zero) return;
    _lastKnownPosition = position;
  }

  List<AudiobookIntent> complete(DateTime now, {Duration? position}) {
    if (!_active) return const [];
    if (position != null) _setPosition(position);
    _active = false;
    _paused = false;

    return [
      AudiobookIntent(
        type: AudiobookIntentType.sessionCompleted,
        at: now,
        mode: _mode,
        position: _lastKnownPosition,
      ),
    ];
  }

  List<AudiobookIntent> exit(DateTime now, {Duration? position}) {
    if (!_active && !_paused) return const [];
    if (position != null) _setPosition(position);
    _active = false;
    _paused = false;

    return [
      AudiobookIntent(
        type: AudiobookIntentType.sessionExited,
        at: now,
        mode: _mode,
        position: _lastKnownPosition,
      ),
    ];
  }

  void reset() {
    _active = false;
    _paused = false;
    _lastKnownPosition = null;
  }

  void _setPosition(Duration position) {
    if (position >= Duration.zero) {
      _lastKnownPosition = position;
    }
  }
}
