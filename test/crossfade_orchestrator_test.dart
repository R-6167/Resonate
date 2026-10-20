import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/crossfade_orchestrator.dart';

void main() {
  group('CrossfadeOrchestrator timing', () {
    test('preserves standard crossfade timing windows', () {
      final timing = CrossfadeOrchestrator.timing(
        configuredDurationMs: 3000,
        djActive: false,
      );

      expect(timing.effectiveFadeMs, 3000);
      expect(timing.preloadWindowMs, 13000);
      expect(timing.fadeArmWindowMs, 5000);
      expect(timing.triggerWindowMs, 4500);
    });

    test('clamps DJ fade duration before deriving trigger window', () {
      final timing = CrossfadeOrchestrator.timing(
        configuredDurationMs: 12000,
        djActive: true,
      );

      expect(timing.effectiveFadeMs, 6500);
      expect(timing.preloadWindowMs, 22000);
      expect(timing.fadeArmWindowMs, 14000);
      expect(timing.triggerWindowMs, 9500);
    });

    test('keeps preload window bounded for long configured fades', () {
      final timing = CrossfadeOrchestrator.timing(
        configuredDurationMs: 12000,
        djActive: false,
      );

      expect(timing.preloadWindowMs, 22000);
      expect(timing.fadeArmWindowMs, 14000);
      expect(timing.triggerWindowMs, 16000);
    });
  });
}
