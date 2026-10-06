import '../models/resonate_mode.dart';
import '../models/work_intent.dart';

/// Deterministic Work Mode session boundary.
///
/// Work Mode does not own playback, timers, notifications, or focus tracking.
/// The host app may consume the intents to coordinate those existing systems.
class WorkCoordinator {
  ResonateMode _mode = ResonateMode.work;
  bool _active = false;
  bool _paused = false;

  ResonateMode get mode => _mode;
  bool get isActive => _active;
  bool get isPaused => _paused;

  void setMode(ResonateMode mode) {
    _mode = mode;
  }

  List<WorkIntent> start(DateTime now) {
    if (_active) return const [];
    _active = true;
    _paused = false;
    return [
      WorkIntent(type: WorkIntentType.sessionStarted, at: now, mode: _mode),
    ];
  }

  List<WorkIntent> pause(DateTime now) {
    if (!_active || _paused) return const [];
    _paused = true;
    return [
      WorkIntent(type: WorkIntentType.sessionPaused, at: now, mode: _mode),
    ];
  }

  List<WorkIntent> resume(DateTime now) {
    if (!_active || !_paused) return const [];
    _paused = false;
    return [
      WorkIntent(type: WorkIntentType.sessionResumed, at: now, mode: _mode),
    ];
  }

  List<WorkIntent> complete(DateTime now) {
    if (!_active) return const [];
    _active = false;
    _paused = false;
    return [
      WorkIntent(type: WorkIntentType.sessionCompleted, at: now, mode: _mode),
    ];
  }

  /// Leaves Work Mode without pretending that the work session was completed.
  List<WorkIntent> exit(DateTime now) {
    if (!_active && !_paused) return const [];
    _active = false;
    _paused = false;
    return [
      WorkIntent(type: WorkIntentType.sessionExited, at: now, mode: _mode),
    ];
  }

  void reset() {
    _active = false;
    _paused = false;
  }
}
