import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/completion_ownership_policy.dart';

void main() {
  group('CompletionOwnershipPolicy', () {
    test('accepts completion for the currently owned song', () {
      expect(
        CompletionOwnershipPolicy.shouldIgnoreStaleCompletion(
          currentSongId: 'song-a',
          completedSongId: 'song-a',
          crossfadeInProgress: false,
          automaticCrossfadeInFlight: false,
        ),
        isFalse,
      );
    });

    test('ignores an outgoing song completion after ownership moved', () {
      expect(
        CompletionOwnershipPolicy.shouldIgnoreStaleCompletion(
          currentSongId: 'song-b',
          completedSongId: 'song-a',
          crossfadeInProgress: false,
          automaticCrossfadeInFlight: false,
        ),
        isTrue,
      );
    });

    test('does not classify completion as stale while a transition owns it', () {
      for (final active in [true, false]) {
        expect(
          CompletionOwnershipPolicy.shouldIgnoreStaleCompletion(
            currentSongId: 'song-b',
            completedSongId: 'song-a',
            crossfadeInProgress: active,
            automaticCrossfadeInFlight: !active,
          ),
          isFalse,
        );
      }
    });

    test('preserves existing behavior when there is no current song identity', () {
      expect(
        CompletionOwnershipPolicy.shouldIgnoreStaleCompletion(
          currentSongId: null,
          completedSongId: 'song-a',
          crossfadeInProgress: false,
          automaticCrossfadeInFlight: false,
        ),
        isFalse,
      );
    });
  });
}
