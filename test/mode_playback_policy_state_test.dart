import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/mode_playback_policy_state.dart';

void main() {
  group('ModePlaybackPolicyState', () {
    test('preserves legacy defaults before Modes publishes a policy', () {
      final state = ModePlaybackPolicyState();
      expect(state.crossfadeAllowed, isTrue);
      expect(state.shuffleAllowed, isTrue);
      expect(state.preciseResume, isFalse);
    });

    test('updates all gates and reports whether values changed', () {
      final state = ModePlaybackPolicyState();
      expect(state.update(
        crossfadeAllowed: false,
        shuffleAllowed: false,
        preciseResume: true,
      ), isTrue);
      expect(state.crossfadeAllowed, isFalse);
      expect(state.shuffleAllowed, isFalse);
      expect(state.preciseResume, isTrue);

      expect(state.update(
        crossfadeAllowed: false,
        shuffleAllowed: false,
        preciseResume: true,
      ), isFalse);
    });

    test('re-enables gates independently on a later policy update', () {
      final state = ModePlaybackPolicyState();
      state.update(
        crossfadeAllowed: false,
        shuffleAllowed: false,
        preciseResume: true,
      );

      expect(state.update(
        crossfadeAllowed: true,
        shuffleAllowed: false,
        preciseResume: false,
      ), isTrue);
      expect(state.crossfadeAllowed, isTrue);
      expect(state.shuffleAllowed, isFalse);
      expect(state.preciseResume, isFalse);
    });
  });
}
