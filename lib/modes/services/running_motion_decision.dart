import '../models/motion_state.dart';
import '../models/running_automation_policy.dart';

/// Decisions emitted by Running Mode's movement layer.
///
/// This engine never controls playback. The host decides whether/how to act
/// on an emitted intent.
enum RunningMotionDecision {
  maintain,
  suggestPause,
  suggestResume,
}

class RunningMotionDecisionEngine {
  final RunningAutomationPolicy policy;
  MotionState _state = MotionState.unknown;
  DateTime? _stateSince;
  DateTime? _lastMovingAt;
  DateTime? _lastDecisionAt;
  bool _automationPausedPlayback = false;
  bool _userPausedPlayback = false;

  RunningMotionDecisionEngine({this.policy = const RunningAutomationPolicy()});

  MotionState get state => _state;
  bool get automationPausedPlayback => _automationPausedPlayback;

  /// Records the user's explicit playback choice. An explicit user pause is
  /// never overridden by movement-based resume automation.
  void setUserPaused(bool paused) {
    _userPausedPlayback = paused;
    if (paused) _automationPausedPlayback = false;
  }

  RunningMotionDecision ingest(
    MotionState state,
    DateTime now, {
    required bool isPlaying,
  }) {
    if (_state != state) {
      _state = state;
      _stateSince = now;
    }
    if (state == MotionState.moving) {
      _lastMovingAt = now;
    }

    if (_stateSince == null || !_isDecisionAllowed(now)) {
      return RunningMotionDecision.maintain;
    }

    final stableFor = now.difference(_stateSince!);

    if (policy.suggestPauseAfterStationary &&
        (state == MotionState.stationary || state == MotionState.stopped) &&
        _stationaryDuration(now) >= policy.stationaryGracePeriod &&
        isPlaying &&
        !_userPausedPlayback &&
        !_automationPausedPlayback) {
      _automationPausedPlayback = true;
      _lastDecisionAt = now;
      return RunningMotionDecision.suggestPause;
    }

    if (policy.suggestResumeAfterMoving &&
        state == MotionState.moving &&
        stableFor >= policy.movingGracePeriod &&
        !isPlaying &&
        _automationPausedPlayback &&
        !_userPausedPlayback) {
      _automationPausedPlayback = false;
      _lastDecisionAt = now;
      return RunningMotionDecision.suggestResume;
    }

    return RunningMotionDecision.maintain;
  }

  bool _isDecisionAllowed(DateTime now) {
    final last = _lastDecisionAt;
    return last == null || now.difference(last) >= policy.decisionCooldown;
  }
}
