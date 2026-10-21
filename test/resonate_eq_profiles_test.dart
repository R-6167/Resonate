import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/providers/equalizer_provider.dart';

void main() {
  group('Resonate first-party EQ profiles', () {
    test('are available alongside every classic built-in preset', () {
      final classicNames =
          EqualizerProvider.builtInPresets.map((preset) => preset.name).toSet();
      final resonateNames = EqualizerProvider.resonatePresets
          .map((preset) => preset.name)
          .toSet();

      expect(resonateNames, {
        'Resonate Signature',
        'Resonate Warmth',
        'Resonate Clarity',
        'Resonate Afterhours',
        'Resonate Pulse',
      });
      expect(resonateNames.intersection(classicNames), isEmpty);
      expect(EqualizerProvider.resonatePresets, hasLength(5));
      expect(
        EqualizerProvider.resonatePresets.every(
          (preset) => preset.category == 'Resonate',
        ),
        isTrue,
      );
    });

    test('use finite, restrained 10-band curves within the supported range', () {
      for (final preset in EqualizerProvider.resonatePresets) {
        expect(preset.gains, hasLength(10), reason: preset.name);
        expect(preset.gains.every((gain) => gain.isFinite), isTrue,
            reason: preset.name);
        expect(preset.gains.every((gain) => gain >= -12 && gain <= 12), isTrue,
            reason: preset.name);
        expect(preset.gains.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(2.5),
            reason: preset.name);
        expect(preset.gains.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(-1),
            reason: preset.name);
      }
    });

    test('expand onto the studio grid without losing the profile endpoints', () {
      for (final preset in EqualizerProvider.resonatePresets) {
        final expanded = EqualizerProvider.expandGainsToStudio(preset.gains);
        expect(expanded, hasLength(EqualizerProvider.studioFrequencies.length));
        expect(expanded.first, closeTo(preset.gains.first, 0.0001));
        expect(expanded.last, closeTo(preset.gains.last, 0.0001));
        expect(expanded.every((gain) => gain.isFinite), isTrue);
      }
    });

    test('each profile has a distinct curve', () {
      final curves = EqualizerProvider.resonatePresets
          .map((preset) => preset.gains.join(','))
          .toSet();
      expect(curves, hasLength(EqualizerProvider.resonatePresets.length));
    });
  });
}
