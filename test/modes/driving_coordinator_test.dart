import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/modes/integration/mode_context_port.dart';
import 'package:resonate/modes/models/driving_intent.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/services/driving_coordinator.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  test('car context produces a Driving suggestion when not already driving', () {
    final coordinator = DrivingCoordinator();
    final intents = coordinator.ingestContext(
      ModeAudioContext.car,
      t0,
    );

    expect(intents.map((i) => i.type), [
      DrivingIntentType.carContextDetected,
      DrivingIntentType.suggestDriving,
    ]);
  });

  test('auto-enter remains an intent decision, never a mode mutation', () {
    final coordinator = DrivingCoordinator();
    final intents = coordinator.ingestContext(
      ModeAudioContext.car,
      t0,
      autoEnterEnabled: true,
    );

    expect(intents.last.type, DrivingIntentType.suggestDriving);
    expect(coordinator.mode, ResonateMode.normal);
  });

  test('already-driving car context emits active state', () {
    final coordinator = DrivingCoordinator(mode: ResonateMode.driving);
    final intents = coordinator.ingestContext(ModeAudioContext.car, t0);

    expect(intents.last.type, DrivingIntentType.drivingActive);
  });

  test('non-car context is ignored until it changes', () {
    final coordinator = DrivingCoordinator();
    expect(coordinator.ingestContext(ModeAudioContext.unknown, t0), isEmpty);

    final intents = coordinator.ingestContext(
      ModeAudioContext.unknown,
      t0.add(const Duration(seconds: 1)),
    );
    expect(intents, isEmpty);
  });

  test('leaving car while Driving emits inactive boundary', () {
    final coordinator = DrivingCoordinator(mode: ResonateMode.driving);
    coordinator.ingestContext(ModeAudioContext.car, t0);

    final intents = coordinator.ingestContext(
      ModeAudioContext.unknown,
      t0.add(const Duration(minutes: 1)),
    );

    expect(intents.map((i) => i.type), [
      DrivingIntentType.carContextLost,
      DrivingIntentType.drivingInactive,
    ]);
  });

  test('context changes are deterministic and do not duplicate events', () {
    final coordinator = DrivingCoordinator();
    coordinator.ingestContext(ModeAudioContext.car, t0);

    expect(
      coordinator.ingestContext(
        ModeAudioContext.car,
        t0.add(const Duration(seconds: 5)),
      ),
      isEmpty,
    );
  });
}
