import 'dart:math' show Random;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate/dj_engine/core/dj_policy.dart';
import 'package:resonate/dj_engine/core/dj_types.dart';
import 'package:resonate/services/dj_sfx_rack.dart';

const safePool = <DjSfxPreset>{
  DjSfxPreset.tightGlue,
  DjSfxPreset.dryEcho,
  DjSfxPreset.echo,
  DjSfxPreset.filterOpen,
  DjSfxPreset.filterClose,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<DjSfxPreset> selectPreset(DjSfxRack rack, {required DjSfxPreset preferred, required DjAggressiveness aggressiveness}) async {
    await rack.engage(energyScore: 0.5, preset: preferred, aggressiveness: aggressiveness);
    final selected = rack.activePreset!;
    await rack.restore();
    return selected;
  }

  group('DJ one-shot sample gain', () {
    test('uses a conservative base gain and reduces it for higher energy', () {
      expect(djSfxOneShotVolumeForEnergy(0.2), 0.12);
      expect(djSfxOneShotVolumeForEnergy(0.7), 0.10);
      expect(djSfxOneShotVolumeForEnergy(0.9), 0.08);
    });

    test('normalizes out-of-range and non-finite energy scores', () {
      expect(djSfxOneShotVolumeForEnergy(double.nan), 0.12);
      expect(djSfxOneShotVolumeForEnergy(double.infinity), 0.12);
      expect(djSfxOneShotVolumeForEnergy(-1), 0.12);
      expect(djSfxOneShotVolumeForEnergy(2), 0.08);
    });
  });

  group('DjSfxRack usage fairness', () {
    test('rotates after two uses and exhausts the eligible pool fairly', () async {
      final rack = DjSfxRack(random: _SequenceRandom());
      final counts = <DjSfxPreset, int>{};
      for (var i = 0; i < 10; i++) {
        final selected = await selectPreset(rack, preferred: DjSfxPreset.tightGlue, aggressiveness: DjAggressiveness.safe);
        counts[selected] = (counts[selected] ?? 0) + 1;
        expect(counts[selected], lessThanOrEqualTo(2), reason: 'Effect $selected exceeded its two-use allowance at pick $i');
      }
      expect(counts.keys.toSet(), containsAll(safePool));
      expect(counts.values, everyElement(2));
      expect(await selectPreset(rack, preferred: DjSfxPreset.tightGlue, aggressiveness: DjAggressiveness.safe), DjSfxPreset.tightGlue);
    });

    test('safe aggressiveness never selects outside its eligible pool', () async {
      final rack = DjSfxRack(random: _SequenceRandom());
      for (var i = 0; i < 12; i++) {
        await rack.engage(energyScore: 0.5, transitionKind: DjTransitionKind.safeCrossfade, aggressiveness: DjAggressiveness.safe);
        expect(safePool, contains(rack.activePreset));
        await rack.restore();
      }
    });

    test('repeat and repeat-restart requests use non-seeking SFX instead', () async {
      final rack = DjSfxRack(random: _SequenceRandom());
      for (final requested in <DjSfxPreset>[
        DjSfxPreset.repeat,
        DjSfxPreset.repeatRestart,
      ]) {
        await rack.engage(
          energyScore: 0.5,
          preset: requested,
          aggressiveness: DjAggressiveness.balanced,
        );
        expect(
          rack.activePreset,
          isNot(anyOf(DjSfxPreset.repeat, DjSfxPreset.repeatRestart)),
          reason: '$requested must not seek/restart the outgoing track during a fade',
        );
        await rack.restore();
      }
    });

    test('phrase blends never choose repeat/restart SFX in musical mode', () async {
      final rack = DjSfxRack(random: _SequenceRandom());
      for (var i = 0; i < 20; i++) {
        await rack.engage(
          energyScore: 0.5,
          transitionKind: DjTransitionKind.phraseBlend,
          aggressiveness: DjAggressiveness.musical,
        );
        expect(
          rack.activePreset,
          isNot(anyOf(DjSfxPreset.repeat, DjSfxPreset.repeatRestart)),
          reason: 'phrase blend $i must use a non-seeking effect',
        );
        await rack.restore();
      }
    });
  });
}

class _SequenceRandom implements Random {
  int _next = 0;
  @override
  int nextInt(int max) => (_next++ % max);
  @override
  bool nextBool() => nextInt(2) == 0;
  @override
  double nextDouble() => nextInt(1000) / 1000;
}
