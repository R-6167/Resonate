import 'package:flutter_test/flutter_test.dart';
import 'package:resonate_modes_lab/modes/models/motion_state.dart';
import 'package:resonate_modes_lab/modes/models/running_automation_policy.dart';
import 'package:resonate_modes_lab/modes/services/running_motion_decision.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  test('transient stop does not request a pause', () {
    final engine = RunningMotionDecisionEngine();
    expect(engine.ingest(MotionState.moving, t0, isPlaying: true), RunningMotionDecision.maintain);
    expect(
      engine.ingest(MotionState.stopped, t0.add(const Duration(seconds: 10)), isPlaying: true),
      RunningMotionDecision.maintain,
    );
  });

  test('sustained stationary state requests one pause', () {
    final engine = RunningMotionDecisionEngine();
    engine.ingest(MotionState.moving, t0, isPlaying: true);
    expect(
      engine.ingest(MotionState.stationary, t0.add(const Duration(seconds: 15)), isPlaying: true),
      RunningMotionDecision.suggestPause,
    );
    expect(
      engine.ingest(MotionState.stationary, t0.add(const Duration(seconds: 20)), isPlaying: false),
      RunningMotionDecision.maintain,
    );
  });

  test('moving must be stable before automation resumes', () {
    final engine = RunningMotionDecisionEngine();
    engine.ingest(MotionState.stationary, t0, isPlaying: true);
    expect(
      engine.ingest(MotionState.stationary, t0.add(const Duration(seconds: 15)), isPlaying: true),
      RunningMotionDecision.suggestPause,
    );
    expect(
      engine.ingest(MotionState.moving, t0.add(const Duration(seconds: 20)), isPlaying: false),
      RunningMotionDecision.maintain,
    );
    expect(
      engine.ingest(MotionState.moving, t0.add(const Duration(seconds: 25)), isPlaying: false),
      RunningMotionDecision.suggestResume,
    );
  });

  test('explicit user pause blocks automatic resume', () {
    final engine = RunningMotionDecisionEngine();
    engine.ingest(MotionState.stationary, t0, isPlaying: true);
    expect(
      engine.ingest(MotionState.stationary, t0.add(const Duration(seconds: 15)), isPlaying: true),
      RunningMotionDecision.suggestPause,
    );
    engine.setUserPaused(true);
    expect(
      engine.ingest(MotionState.moving, t0.add(const Duration(seconds: 30)), isPlaying: false),
      RunningMotionDecision.maintain,
    );
  });

  test('unknown movement never creates an automation decision', () {
    final engine = RunningMotionDecisionEngine();
    expect(engine.ingest(MotionState.unknown, t0, isPlaying: true), RunningMotionDecision.maintain);
    expect(
      engine.ingest(MotionState.unknown, t0.add(const Duration(minutes: 5)), isPlaying: true),
      RunningMotionDecision.maintain,
    );
  });

  test('cooldown prevents immediate reverse decisions', () {
    final engine = RunningMotionDecisionEngine(
      policy: const RunningAutomationPolicy(decisionCooldown: Duration(seconds: 10)),
    );
    engine.ingest(MotionState.stationary, t0);
    expect(
      engine.ingest(MotionState.stationary, t0.add(const Duration(seconds: 15)), isPlaying: true),
      RunningMotionDecision.suggestPause,
    );
    expect(
      engine.ingest(MotionState.moving, t0.add(const Duration(seconds: 20)), isPlaying: false),
      RunningMotionDecision.maintain,
    );
  });
}
