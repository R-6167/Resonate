import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate/modes/integration/mode_motion_port.dart';
import 'package:resonate/modes/models/motion_state.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/models/running_intent.dart';
import 'package:resonate/modes/models/running_session_state.dart';
import 'package:resonate/modes/providers/mode_provider.dart';

class _FakeMotion implements ModeMotionPort {
  MotionState value = MotionState.unknown;
  final List<void Function()> _listeners = <void Function()>[];
  bool started = false;

  @override
  MotionState get motionState => value;
  @override
  void start() => started = true;
  @override
  void stop() => started = false;
  @override
  void addListener(void Function() listener) => _listeners.add(listener);
  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void emit(MotionState next) {
    value = next;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Running mode starts motion adapter and session', () async {
    final motion = _FakeMotion();
    final intents = <RunningIntent>[];
    final modes = ModeProvider();
    modes.attachMotion(motion, isPlaying: () => true, onIntent: intents.add);
    await modes.ready;
    await modes.setMode(ResonateMode.running);

    expect(motion.started, isTrue);
    expect(modes.runningSessionActive, isTrue);
    expect(intents.first.type, RunningIntentType.sessionStarted);
    modes.dispose();
  });

  test('motion events reach Running only while Running mode is active', () async {
    final motion = _FakeMotion();
    final modes = ModeProvider();
    modes.attachMotion(motion, isPlaying: () => true);
    await modes.ready;

    motion.emit(MotionState.moving);
    expect(modes.lastRunningIntents, isEmpty);

    await modes.setMode(ResonateMode.running);
    motion.emit(MotionState.moving);
    expect(modes.lastRunningIntents.map((i) => i.type), [
      RunningIntentType.motionChanged,
    ]);
    modes.dispose();
  });

  test('leaving Running stops motion and closes session', () async {
    final motion = _FakeMotion();
    final intents = <RunningIntent>[];
    final modes = ModeProvider();
    modes.attachMotion(motion, isPlaying: () => false, onIntent: intents.add);
    await modes.ready;
    await modes.setMode(ResonateMode.running);
    await modes.setMode(ResonateMode.normal);

    expect(motion.started, isFalse);
    expect(modes.runningSessionState, RunningSessionState.idle);
    expect(intents.map((i) => i.type), [
      RunningIntentType.sessionStarted,
      RunningIntentType.sessionExited,
    ]);
    modes.dispose();
  });
}
