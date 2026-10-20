import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/dj_engine/dj_engine.dart';

void main() {
  const corrector = DjBeatDriftCorrector();

  test('ignores small phase jitter', () {
    expect(
      corrector.decide(driftMs: 12, bpm: 120, baseSpeed: 1.0),
      isNull,
    );
  });

  test('gently slows an incoming track that is ahead', () {
    final decision = corrector.decide(
      driftMs: 45,
      bpm: 120,
      baseSpeed: 1.0,
    );

    expect(decision, isNotNull);
    expect(decision!.speed, lessThan(1.0));
    expect(decision.speed, greaterThan(0.99));
    expect(decision.holdMs, 650);
  });

  test('gently speeds up an incoming track that is behind', () {
    final decision = corrector.decide(
      driftMs: -45,
      bpm: 120,
      baseSpeed: 1.0,
    );

    expect(decision, isNotNull);
    expect(decision!.speed, greaterThan(1.0));
    expect(decision.speed, lessThan(1.01));
  });

  test('rejects drift too large for gentle correction', () {
    expect(
      corrector.decide(driftMs: 100, bpm: 120, baseSpeed: 1.0),
      isNull,
    );
  });

  test('rejects invalid tempo', () {
    expect(
      corrector.decide(driftMs: 45, bpm: 30, baseSpeed: 1.0),
      isNull,
    );
    expect(
      corrector.decide(driftMs: 45, bpm: 260, baseSpeed: 1.0),
      isNull,
    );
  });

  test('preserves a tempo-matched base speed', () {
    final decision = corrector.decide(
      driftMs: -45,
      bpm: 100,
      baseSpeed: 1.08,
    );

    expect(decision, isNotNull);
    expect(decision!.speed, closeTo(1.08648, 0.00001));
  });
}
