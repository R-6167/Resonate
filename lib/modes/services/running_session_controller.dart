import '../models/motion_state.dart';
import '../models/running_session_state.dart';

/// Deterministic Running Mode session lifecycle.
///
/// This class owns session state only. It does not start sensors or control
/// playback. The host application supplies motion/playback facts and consumes
/// the resulting state or intents.
class RunningSessionController {
  RunningSessionState _state = RunningSessionState.idle;
  DateTime? _startedAt;
  DateTime? _endedAt;
  Duration _accumulatedActive = Duration.zero;
  DateTime? _activeSince;

  RunningSessionState get state => _state;
  DateTime? get startedAt => _startedAt;
  DateTime? get endedAt => _endedAt;
  Duration get elapsedActive {
    if (_state == RunningSessionState.active && _activeSince != null) {
      return _accumulatedActive + DateTime.now().difference(_activeSince!);
    }
    return _accumulatedActive;
  }

  /// Starts a fresh session. Calling start while already active is idempotent.
  void start(DateTime now) {
    if (_state == RunningSessionState.active) return;
    _state = RunningSessionState.active;
    _startedAt ??= now;
    _endedAt = null;
    _activeSince = now;
  }

  /// Records an intentional pause without ending the run session.
  void pause(DateTime now) {
    if (_state != RunningSessionState.active) return;
    _accumulateActive(now);
    _state = RunningSessionState.paused;
    _activeSince = null;
  }

  /// Resumes a paused session. It cannot resurrect a completed session.
  void resume(DateTime now) {
    if (_state != RunningSessionState.paused) return;
    _state = RunningSessionState.active;
    _activeSince = now;
  }

  /// Finishes the session and freezes its elapsed active duration.
  void complete(DateTime now) {
    if (_state == RunningSessionState.completed) return;
    if (_state == RunningSessionState.active) _accumulateActive(now);
    _state = RunningSessionState.completed;
    _endedAt = now;
    _activeSince = null;
  }

  /// Leaves Running Mode without pretending the run completed.
  /// A future session can be started cleanly.
  void exit(DateTime now) {
    if (_state == RunningSessionState.active) _accumulateActive(now);
    _state = RunningSessionState.idle;
    _endedAt = now;
    _activeSince = null;
  }

  /// A completed/old session is cleared before a new run.
  void reset() {
    _state = RunningSessionState.idle;
    _startedAt = null;
    _endedAt = null;
    _accumulatedActive = Duration.zero;
    _activeSince = null;
  }

  void _accumulateActive(DateTime now) {
    final since = _activeSince;
    if (since != null && now.isAfter(since)) {
      _accumulatedActive += now.difference(since);
    }
  }
}
