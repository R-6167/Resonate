import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/crossfade_transition_guard.dart';

void main() {
  group('CrossfadeTransitionGuard', () {
    const guard = CrossfadeTransitionGuard(
      userTransportEpoch: 4,
      transitionGeneration: 9,
      outgoingSongId: 'song-a',
      queueIndex: 2,
    );

    test('matches the exact transition snapshot', () {
      expect(
        guard.matches(
          userTransportEpoch: 4,
          transitionGeneration: 9,
          currentSongId: 'song-a',
          queueIndex: 2,
        ),
        isTrue,
      );
    });

    test('rejects a newer user transport epoch', () {
      expect(
        guard.matches(
          userTransportEpoch: 5,
          transitionGeneration: 9,
          currentSongId: 'song-a',
          queueIndex: 2,
        ),
        isFalse,
      );
    });

    test('rejects a transition when the current song identity is absent', () {
      expect(
        guard.matches(
          userTransportEpoch: 4,
          transitionGeneration: 9,
          currentSongId: null,
          queueIndex: 2,
        ),
        isFalse,
      );
    });

    test('rejects a newer transition, song, or queue index', () {
      expect(
        guard.matches(
          userTransportEpoch: 4,
          transitionGeneration: 10,
          currentSongId: 'song-a',
          queueIndex: 2,
        ),
        isFalse,
      );
      expect(
        guard.matches(
          userTransportEpoch: 4,
          transitionGeneration: 9,
          currentSongId: 'song-b',
          queueIndex: 2,
        ),
        isFalse,
      );
      expect(
        guard.matches(
          userTransportEpoch: 4,
          transitionGeneration: 9,
          currentSongId: 'song-a',
          queueIndex: 3,
        ),
        isFalse,
      );
    });
  });
}
