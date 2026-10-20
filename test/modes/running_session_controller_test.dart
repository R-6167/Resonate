import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/modes/models/running_session_state.dart';
import 'package:resonate/modes/services/running_session_controller.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  test('starts idle and enters active', () {
    final controller = RunningSessionController();
    expect(controller.state, RunningSessionState.idle);
    controller.start(t0);
    expect(controller.state, RunningSessionState.active);
    expect(controller.startedAt, t0);
  });

  test('pause and resume preserve the same session', () {
    final controller = RunningSessionController();
    controller.start(t0);
    controller.pause(t0.add(const Duration(minutes: 5)));
    expect(controller.state, RunningSessionState.paused);
    controller.resume(t0.add(const Duration(minutes: 7)));
    expect(controller.state, RunningSessionState.active);
    expect(controller.startedAt, t0);
  });

  test('completion freezes the active duration', () {
    final controller = RunningSessionController();
    controller.start(t0);
    controller.complete(t0.add(const Duration(minutes: 30)));
    expect(controller.state, RunningSessionState.completed);
    expect(controller.endedAt, t0.add(const Duration(minutes: 30)));
    expect(controller.elapsedActive, const Duration(minutes: 30));
  });

  test('paused time is excluded from active duration', () {
    final controller = RunningSessionController();
    controller.start(t0);
    controller.pause(t0.add(const Duration(minutes: 10)));
    controller.resume(t0.add(const Duration(minutes: 20)));
    controller.complete(t0.add(const Duration(minutes: 35)));
    expect(controller.elapsedActive, const Duration(minutes: 25));
  });

  test('leaving Running returns to idle without marking completion', () {
    final controller = RunningSessionController();
    controller.start(t0);
    controller.exit(t0.add(const Duration(minutes: 12)));
    expect(controller.state, RunningSessionState.idle);
    expect(controller.endedAt, t0.add(const Duration(minutes: 12)));
  });

  test('completed session cannot resume', () {
    final controller = RunningSessionController();
    controller.start(t0);
    controller.complete(t0.add(const Duration(minutes: 20)));
    controller.resume(t0.add(const Duration(minutes: 25)));
    expect(controller.state, RunningSessionState.completed);
  });

  test('reset creates a clean session boundary', () {
    final controller = RunningSessionController();
    controller.start(t0);
    controller.complete(t0.add(const Duration(minutes: 20)));
    controller.reset();
    expect(controller.state, RunningSessionState.idle);
    expect(controller.startedAt, isNull);
    expect(controller.elapsedActive, Duration.zero);
  });
}
