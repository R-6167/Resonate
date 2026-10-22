import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/providers/equalizer_provider.dart';

void main() {
  group('Equalizer preset catalog', () {
    test('first-party Resonate profiles resolve to distinct, bounded curves', () {
      final profiles = EqualizerProvider.resonatePresets;
      expect(profiles, hasLength(10));
      expect(profiles.map((p) => p.name).toSet(), hasLength(10));
      expect(
        profiles.map((p) => p.name),
        containsAll([
          'Resonate Signature',
          'Resonate Warmth',
          'Resonate Clarity',
          'Resonate Afterhours',
          'Resonate Pulse',
          'Resonate Deep Bass',
          'Resonate Drive',
          'Resonate Focus',
          'Resonate Speaker',
          'Resonate Vocal Presence',
        ]),
      );

      final curves = <String>{};
      for (final profile in profiles) {
        expect(profile.gains, hasLength(10), reason: profile.name);
        final expanded = EqualizerProvider.normalizePresetGains(profile.gains);
        expect(expanded, hasLength(EqualizerProvider.studioFrequencies.length));
        expect(
          expanded.every((gain) => gain.isFinite && gain >= -12 && gain <= 12),
          isTrue,
          reason: profile.name,
        );
        curves.add(expanded.join(','));
      }
      expect(curves, hasLength(10));
    });

    test('resolver returns the exact named built-in, Resonate, or custom profile', () {
      const custom = EqualizerPreset(
        name: 'My curve',
        category: 'Custom',
        gains: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        isCustom: true,
      );

      expect(
        EqualizerProvider.resolvePresetByName('Resonate Signature')?.gains,
        EqualizerProvider.resonatePresets.first.gains,
      );
      expect(
        EqualizerProvider.resolvePresetByName('Warm')?.gains,
        EqualizerProvider.builtInPresets.firstWhere((p) => p.name == 'Warm').gains,
      );
      expect(
        EqualizerProvider.resolvePresetByName('My curve', custom: [custom])?.gains,
        custom.gains,
      );
      expect(
        EqualizerProvider.resolvePresetByName('deleted preset', custom: [custom]),
        isNull,
      );
    });

    test('legacy ten-band curves expand and current studio curves remain intact', () {
      final legacy = [for (var i = 0; i < 10; i++) i.toDouble() - 4];
      expect(EqualizerProvider.normalizePresetGains(legacy), hasLength(31));

      final studio = List<double>.filled(31, 1.25);
      expect(EqualizerProvider.normalizePresetGains(studio), studio);
    });

    test('rejects malformed or unsafe preset curves', () {
      expect(
        () => EqualizerProvider.normalizePresetGains([1, 2, 3]),
        throwsFormatException,
      );
      expect(
        () => EqualizerProvider.normalizePresetGains([
          0, 0, 0, 0, 0, 0, 0, 0, 0, double.nan,
        ]),
        throwsFormatException,
      );
      expect(
        () => EqualizerProvider.normalizePresetGains([
          13, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ]),
        throwsFormatException,
      );
    });

    test('custom names cannot shadow built-in or Resonate profiles', () {
      final collide = EqualizerProvider.uniqueCustomPresetName(
        'resonate signature',
      );
      expect(collide, 'resonate signature (Custom)');

      final second = EqualizerProvider.uniqueCustomPresetName(
        'resonate signature',
        existingCustomPresets: [
          EqualizerPreset(
            name: collide,
            category: 'Custom',
            gains: List<double>.filled(31, 0),
            isCustom: true,
          ),
        ],
      );
      expect(second, 'resonate signature (Custom 2)');

      final replacement = EqualizerProvider.uniqueCustomPresetName(
        'My curve',
        existingCustomPresets: [
          EqualizerPreset(
            name: 'My curve',
            category: 'Custom',
            gains: List<double>.filled(31, 0),
            isCustom: true,
          ),
        ],
        replacingName: 'My curve',
      );
      expect(replacement, 'My curve');
    });
  });
}
