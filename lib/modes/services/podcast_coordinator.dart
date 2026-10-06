import '../models/podcast_intent.dart';
import '../models/resonate_mode.dart';

/// Deterministic Podcast Mode coordinator.
///
/// It owns podcast-session intent and precise-resume boundaries only.
/// Playback, position storage, chapters, timers, and media detection remain
/// responsibilities of the host Resonate application.
class PodcastCoordinator {
  ResonateMode _mode = ResonateMode.podcast;
  bool _active = false;
  bool _paused = false;
  Duration? _lastKnownPosition;

  ResonateMode get mode => _mode;
  bool get isActive => _active;
  bool get isPaused => _paused;
  Duration? get lastKnownPosition => _lastKnownPosition;

  void setMode(ResonateMode mode) => _mode = mode;

  List<PodcastIntent> start(DateTime now, {Duration? resumePosition}) {
    if (_active) return const [];
    _active = true;
    _paused = false;
    _lastKnownPosition = resumePosition;
    final intents = <PodcastIntent>[
      PodcastIntent(
        type: PodcastIntentType.sessionStarted,
        at: now,
        mode: _mode,
      ),
      const PodcastIntent(
        type: PodcastIntentType.speedControlsElevated,
        at: _zero,
      ),
    ];
    if (resumePosition != null) {
      intents.add(PodcastIntent(
        type: PodcastIntentType.resumePositionRequired,
        at: now,
        mode: _mode,
        position: resumePosition,
      ));
    }
    return intents;
  }

  List<PodcastIntent> pause(DateTime now, {Duration? position}) {
    if (!_active || _paused) return const [];
    _paused = true;
    if (position != null) _lastKnownPosition = position;
    return [
      PodcastIntent(
        type: PodcastIntentType.sessionPaused,
        at: now,
        mode: _mode,
        position: _lastKnownPosition,
      ),
    ];
  }

  List<PodcastIntent> resume(DateTime now, {Duration? position}) {
    if (!_active || !_paused) return const [];
    _paused = false;
    if (position != null) _lastKnownPosition = position;
    return [
      PodcastIntent(
        type: PodcastIntentType.sessionResumed,
        at: now,
        mode: _mode,
        position: _lastKnownPosition,
      ),
    ];
  }

  List<PodcastIntent> updatePosition(Duration position) {
    if (!_active) return const [];
    if (position < Duration.zero) return const [];
    _lastKnownPosition = position;
    return const [];
  }

  List<PodcastIntent> complete(DateTime now, {Duration? position}) {
    if (!_active) return const [];
    if (position != null) _lastKnownPosition = position;
    _active = false;
    _paused = false;
    return [
      PodcastIntent(
        type: PodcastIntentType.sessionCompleted,
        at: now,
        mode: _mode,
        position: _lastKnownPosition,
      ),
    ];
  }

  List<PodcastIntent> exit(DateTime now, {Duration? position}) {
    if (!_active && !_paused) return const [];
    if (position != null) _lastKnownPosition = position;
    _active = false;
    _paused = false;
    return [
      PodcastIntent(
        type: PodcastIntentType.sessionExited,
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

  static final DateTime _zero = DateTime(1970);
}
