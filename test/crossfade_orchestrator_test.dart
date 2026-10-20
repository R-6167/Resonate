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
      expect(timing.triggerWindowMs, 8350);
    });

    test('keeps preload window bounded for long configured fades', () {
      final timing = CrossfadeOrchestrator.timing(
        configuredDurationMs: 12000,
        djActive: false,
      );

      expect(timing.preloadWindowMs, 22000);
      expect(timing.fadeArmWindowMs, 14000);
      expect(timing.triggerWindowMs, 14400);
    });
  });


  group('CrossfadeOrchestrator gains', () {
    test('starts with outgoing audio only and ends with incoming audio only', () {
      final start = CrossfadeOrchestrator.gains(
        elapsedMs: 0,
        totalMs: 3000,
        fadeType: 'linear',
      );
      final end = CrossfadeOrchestrator.gains(
        elapsedMs: 3000,
        totalMs: 3000,
        fadeType: 'linear',
      );

      expect(start.outgoing, closeTo(1.0, 1e-9));
      expect(start.incoming, closeTo(0.0, 1e-9));
      expect(end.outgoing, closeTo(0.0, 1e-9));
      expect(end.incoming, closeTo(1.0, 1e-9));
    });

    test('keeps every supported curve bounded and progresses monotonically', () {
      for (final fadeType in ['linear', 'ease_in', 'ease_out', 'ease_in_out']) {
        final early = CrossfadeOrchestrator.gains(
          elapsedMs: 750,
          totalMs: 3000,
          fadeType: fadeType,
        );
        final late = CrossfadeOrchestrator.gains(
          elapsedMs: 2250,
          totalMs: 3000,
          fadeType: fadeType,
        );

        expect(early.outgoing, inInclusiveRange(0.0, 1.0));
        expect(early.incoming, inInclusiveRange(0.0, 1.0));
        expect(late.outgoing, inInclusiveRange(0.0, 1.0));
        expect(late.incoming, inInclusiveRange(0.0, 1.0));
        expect(late.outgoing, lessThan(early.outgoing));
        expect(late.incoming, greaterThan(early.incoming));
      }
    });

    test('clamps elapsed time to the fade boundaries', () {
      final before = CrossfadeOrchestrator.gains(
        elapsedMs: -100,
        totalMs: 3000,
        fadeType: 'linear',
      );
      final after = CrossfadeOrchestrator.gains(
        elapsedMs: 4000,
        totalMs: 3000,
        fadeType: 'linear',
      );

      expect(before.outgoing, closeTo(1.0, 1e-9));
      expect(before.incoming, closeTo(0.0, 1e-9));
      expect(after.outgoing, closeTo(0.0, 1e-9));
      expect(after.incoming, closeTo(1.0, 1e-9));
    });
  });
}
