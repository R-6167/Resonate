import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/crossfade_fallback_target.dart';

void main() {
  group('CrossfadeFallbackTarget', () {
    test('advances to the next queue entry', () {
      expect(
        CrossfadeFallbackTarget.nextIndex(
          currentIndex: 1,
          queueLength: 4,
          repeatAll: false,
        ),
        2,
      );
    });

    test('returns no target at the end when repeat-all is disabled', () {
      expect(
        CrossfadeFallbackTarget.nextIndex(
          currentIndex: 3,
          queueLength: 4,
          repeatAll: false,
        ),
        -1,
      );
    });

    test('wraps to the first entry at the end when repeat-all is enabled', () {
      expect(
        CrossfadeFallbackTarget.nextIndex(
          currentIndex: 3,
          queueLength: 4,
          repeatAll: true,
        ),
        0,
      );
    });

    test('returns no target for an empty or invalid queue position', () {
      expect(
        CrossfadeFallbackTarget.nextIndex(
          currentIndex: 0,
          queueLength: 0,
          repeatAll: true,
        ),
        -1,
      );
      expect(
        CrossfadeFallbackTarget.nextIndex(
          currentIndex: -1,
          queueLength: 3,
          repeatAll: true,
        ),
        -1,
      );
      expect(
        CrossfadeFallbackTarget.nextIndex(
          currentIndex: 3,
          queueLength: 3,
          repeatAll: true,
        ),
        -1,
      );
    });
  });
}
