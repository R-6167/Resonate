import 'package:flutter_test/flutter_test.dart';

import '../lib/services/playback_intent_gate.dart';

void main() {
  test('new user intent invalidates older playback work', () {
    final gate = PlaybackIntentGate();
    final first = gate.issue();
    final second = gate.issue();

    expect(gate.isCurrent(first), isFalse);
    expect(gate.isCurrent(second), isTrue);
  });

  test('non-current work can be detected after several commands', () {
    final gate = PlaybackIntentGate();
    final tokens = List<int>.generate(5, (_) => gate.issue());

    for (final token in tokens.take(4)) {
      expect(gate.isCurrent(token), isFalse);
    }
    expect(gate.isCurrent(tokens.last), isTrue);
  });

  test('tokens are strictly increasing', () {
    final gate = PlaybackIntentGate();
    final first = gate.issue();
    final second = gate.issue();
    final third = gate.issue();

    expect(second, greaterThan(first));
    expect(third, greaterThan(second));
    expect(gate.currentToken, third);
  });

  test('a fresh gate has no active intent', () {
    final gate = PlaybackIntentGate();

    expect(gate.currentToken, 0);
    expect(gate.isCurrent(0), isTrue);
  });

  test('latest user intent remains current while older work is pending', () {
    final gate = PlaybackIntentGate();
    final first = gate.issue();
    final second = gate.issue();

    expect(gate.isCurrent(first), isFalse);
    expect(gate.isCurrent(second), isTrue);
  });
}
