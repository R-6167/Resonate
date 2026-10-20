import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:resonate/services/dj_transition_memory.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('learning stays strategy-specific and pair aggregation remains bounded', () async {
    await DjTransitionMemory.recordOutcome(
      fromId: 'a',
      toId: 'b',
      strategy: 'phrase_blend',
      successful: true,
      score: 0.91,
      confidence: 0.88,
      risks: const ['low_confidence'],
      transitionDurationMs: 4200,
      recoveryAttempts: 0,
    );
    await DjTransitionMemory.recordOutcome(
      fromId: 'a',
      toId: 'b',
      strategy: 'beat_blend',
      successful: false,
      score: 0.31,
      confidence: 0.54,
      risks: const ['bass_collision'],
      transitionDurationMs: 2800,
      recoveryAttempts: 1,
    );

    expect(
      await DjTransitionMemory.pairStrategyBias('a', 'b', 'phrase_blend'),
      closeTo(1.0, 0.001),
    );
    expect(
      await DjTransitionMemory.pairStrategyBias('a', 'b', 'beat_blend'),
      closeTo(-1.0, 0.001),
    );
    expect(
      await DjTransitionMemory.pairBias('a', 'b'),
      closeTo(0.0, 0.001),
    );
  });

  test('empty identifiers never write learning state', () async {
    await DjTransitionMemory.recordOutcome(
      fromId: '',
      toId: 'b',
      strategy: 'phrase_blend',
      successful: true,
    );
    expect(
      await DjTransitionMemory.pairStrategyBias('', 'b', 'phrase_blend'),
      0.0,
    );
  });
}
