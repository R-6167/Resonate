import '../models/media_type.dart';
import '../models/motivation_intent.dart';
import '../models/resonate_mode.dart';

class MotivationCoordinator {
  ResonateMode _mode;
  bool _active = false;
  bool _paused = false;
  MediaType? _currentMediaType;

  MotivationCoordinator({ResonateMode mode = ResonateMode.motivation})
      : _mode = mode;

  ResonateMode get mode => _mode;
  bool get isActive => _active;
  bool get isPaused => _paused;
  MediaType? get currentMediaType => _currentMediaType;

  void setMode(ResonateMode mode) => _mode = mode;

  List<MotivationIntent> start(DateTime now) {
    if (_active) return const [];
    _active = true;
    _paused = false;
    _currentMediaType = null;
    return [
      MotivationIntent(type: MotivationIntentType.sessionStarted, at: now),
    ];
  }

  List<MotivationIntent> pause(DateTime now) {
    if (!_active || _paused) return const [];
    _paused = true;
    return [
      MotivationIntent(type: MotivationIntentType.sessionPaused, at: now),
    ];
  }

  List<MotivationIntent> resume(DateTime now) {
    if (!_active || !_paused) return const [];
    _paused = false;
    return [
      MotivationIntent(type: MotivationIntentType.sessionResumed, at: now),
    ];
  }

  List<MotivationIntent> complete(DateTime now) {
    if (!_active) return const [];
    _active = false;
    _paused = false;
    _currentMediaType = null;
    return [
      MotivationIntent(type: MotivationIntentType.sessionCompleted, at: now),
    ];
  }

  List<MotivationIntent> exit(DateTime now) {
    if (!_active) return const [];
    _active = false;
    _paused = false;
    _currentMediaType = null;
    return [
      MotivationIntent(type: MotivationIntentType.sessionExited, at: now),
    ];
  }

  /// Records the currently playing classified content and emits a speech
  /// boundary only when motivation/speech content actually starts.
  List<MotivationIntent> startContent(
    MediaType mediaType,
    DateTime now,
  ) {
    if (!_active) return const [];

    final previous = _currentMediaType;
    _currentMediaType = mediaType;

    if (mediaType != MediaType.motivation || previous == mediaType) {
      return const [];
    }

    return [
      MotivationIntent(
        type: MotivationIntentType.speechStarted,
        at: now,
        mediaType: mediaType,
      ),
    ];
  }

  /// Marks content complete. Motivation speech completion requests a music
  /// follow-up, but the host remains responsible for choosing/reordering
  /// the actual queue.
  List<MotivationIntent> completeContent(
    MediaType mediaType,
    DateTime now,
  ) {
    if (!_active || _currentMediaType != mediaType) return const [];

    _currentMediaType = null;

    if (mediaType != MediaType.motivation) return const [];

    return [
      MotivationIntent(
        type: MotivationIntentType.speechCompleted,
        at: now,
        mediaType: mediaType,
      ),
      MotivationIntent(
        type: MotivationIntentType.musicFollowupSuggested,
        at: now,
        mediaType: MediaType.music,
      ),
    ];
  }

  void reset() {
    _active = false;
    _paused = false;
    _currentMediaType = null;
  }
}
