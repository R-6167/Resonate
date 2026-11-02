import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/player_stream_binder.dart';

class _EngineState {
  const _EngineState(this.playing, this.phase);

  final bool playing;
  final String phase;
}

void main() {
  group('PlayerStreamBinder', () {
    late PlayerStreamBinder binder;
    late StreamController<_EngineState> stateController;
    late StreamController<Duration> positionController;
    late StreamController<Duration?> durationController;

    setUp(() {
      binder = PlayerStreamBinder();
      stateController = StreamController<_EngineState>.broadcast();
      positionController = StreamController<Duration>.broadcast();
      durationController = StreamController<Duration?>.broadcast();
    });

    tearDown(() async {
      binder.cancel();
      await stateController.close();
      await positionController.close();
      await durationController.close();
    });

    test('forwards engine-neutral state, position, and duration events', () async {
      final states = <_EngineState>[];
      final positions = <Duration>[];
      final durations = <Duration?>[];

      binder.bindPlayerState(stateController.stream, states.add);
      binder.bindPosition(positionController.stream, positions.add);
      binder.bindDuration(durationController.stream, durations.add);

      const state = _EngineState(true, 'ready');
      const position = Duration(seconds: 12);
      const duration = Duration(minutes: 3);
      stateController.add(state);
      positionController.add(position);
      durationController.add(duration);
      await Future<void>.delayed(Duration.zero);

      expect(states, [state]);
      expect(positions, [position]);
      expect(durations, [duration]);
    });

    test('cancel stops forwarding subsequent events', () async {
      final positions = <Duration>[];
      binder.bindPosition(positionController.stream, positions.add);
      positionController.add(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      binder.cancel();
      positionController.add(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);

      expect(positions, [const Duration(seconds: 1)]);
    });

    test('rebinding replaces the previous subscription', () async {
      final first = StreamController<Duration>.broadcast();
      final second = StreamController<Duration>.broadcast();
      final positions = <Duration>[];
      binder.bindPosition(first.stream, positions.add);
      binder.bindPosition(second.stream, positions.add);
      first.add(const Duration(seconds: 1));
      second.add(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);

      expect(positions, [const Duration(seconds: 2)]);
      await first.close();
      await second.close();
    });
  });
}
