import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate/modes/integration/mode_context_port.dart';
import 'package:resonate/modes/models/driving_intent.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/providers/mode_provider.dart';

class _FakeContext implements ModeContextPort {
  ModeAudioContext value;
  final List<void Function()> _listeners = <void Function()>[];

  _FakeContext(this.value);

  @override
  ModeAudioContext get audioContext => value;

  @override
  void addListener(void Function() listener) => _listeners.add(listener);

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void set(ModeAudioContext next) {
    value = next;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('live car context is translated into Driving intents', () async {
    final modes = ModeProvider();
    final context = _FakeContext(ModeAudioContext.unknown);
    modes.attachContext(context);
    await modes.ready;

    context.set(ModeAudioContext.car);

    expect(modes.drivingContextActive, isTrue);
    expect(modes.lastDrivingIntents.map((i) => i.type), [
      DrivingIntentType.carContextDetected,
      DrivingIntentType.suggestDriving,
    ]);

    modes.dispose();
  });

  test('entering Driving mode makes the live car boundary active', () async {
    final modes = ModeProvider();
    final context = _FakeContext(ModeAudioContext.car);
    modes.attachContext(context);
    await modes.ready;

    await modes.setMode(ResonateMode.driving);

    expect(modes.drivingContextActive, isTrue);
    expect(modes.lastDrivingIntents, isEmpty);

    modes.dispose();
  });

  test('leaving car context emits Driving inactive boundary', () async {
    final modes = ModeProvider();
    final context = _FakeContext(ModeAudioContext.car);
    modes.attachContext(context);
    await modes.ready;

    await modes.setMode(ResonateMode.driving);
    context.set(ModeAudioContext.unknown);

    expect(modes.lastDrivingIntents.map((i) => i.type), [
      DrivingIntentType.carContextLost,
      DrivingIntentType.drivingInactive,
    ]);

    modes.dispose();
  });
}
