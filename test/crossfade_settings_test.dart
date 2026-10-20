import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/crossfade_settings.dart';

void main() {
  group('CrossfadeSettings', () {
    test('uses safe defaults and clamps duration', () {
      final settings = CrossfadeSettings();
      expect(settings.enabled, isFalse);
      expect(settings.clampedDurationMs, 3000);
      settings.setDurationMs(1);
      expect(settings.durationMs, 500);
      expect(settings.enabled, isTrue);
      settings.setDurationMs(20000);
      expect(settings.durationMs, 12000);
    });

    test('reports only enabled-to-disabled transitions', () {
      final settings = CrossfadeSettings();
      expect(settings.setEnabled(false), isFalse);
      settings.setEnabled(true);
      expect(settings.setEnabled(false), isTrue);
      expect(settings.setEnabled(false), isFalse);
    });

    test('rejects unknown fade curves without overwriting current value', () {
      final settings = CrossfadeSettings();
      expect(settings.setFadeType('ease_in_out'), isTrue);
      expect(settings.fadeType, 'ease_in_out');
      expect(settings.setFadeType('spring'), isFalse);
      expect(settings.fadeType, 'ease_in_out');
    });
  });
}
