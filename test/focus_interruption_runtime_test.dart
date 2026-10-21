import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/focus_interruption_runtime.dart';

void main() {
  group('FocusInterruptionRuntime event ownership', () {
    test('a transport-cancelled fade keeps ownership until a newer focus event', () {
      final runtime = FocusInterruptionRuntime();

      final unduckGeneration = runtime.focusEventGeneration;
      expect(runtime.ownsFocusEventGeneration(unduckGeneration), isTrue);

      // A transport action does not mutate focus-event ownership.
      expect(runtime.ownsFocusEventGeneration(unduckGeneration), isTrue);

      runtime.noteFocusEvent();
      expect(runtime.ownsFocusEventGeneration(unduckGeneration), isFalse);
      expect(
        runtime.ownsFocusEventGeneration(runtime.focusEventGeneration),
        isTrue,
      );
    });

    test('each focus event advances generation exactly once', () {
      final runtime = FocusInterruptionRuntime();

      expect(runtime.noteFocusEvent(), 1);
      expect(runtime.noteFocusEvent(), 2);
      expect(runtime.focusEventGeneration, 2);
    });
  });
}
