import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/services/media3_playback_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Media3PlaybackState.fromMap', () {
    test('parses a normal native state snapshot', () {
      final state = Media3PlaybackState.fromMap(<Object?, Object?>{
        'connected': true,
        'isPlaying': true,
        'playbackState': 3,
        'playWhenReady': true,
        'positionMs': 1250,
        'durationMs': 9000,
        'mediaId': 'content://media/track/1',
        'volume': 0.65,
        'hasError': false,
        'error': null,
      });

      expect(state.connected, isTrue);
      expect(state.isPlaying, isTrue);
      expect(state.playbackState, 3);
      expect(state.position, const Duration(milliseconds: 1250));
      expect(state.duration, const Duration(milliseconds: 9000));
      expect(state.mediaId, 'content://media/track/1');
      expect(state.volume, 0.65);
      expect(state.hasError, isFalse);
    });

    test('clamps invalid negative time and out-of-range volume', () {
      final state = Media3PlaybackState.fromMap(<Object?, Object?>{
        'positionMs': -50,
        'durationMs': -1,
        'volume': 4.0,
      });

      expect(state.position, Duration.zero);
      expect(state.duration, isNull);
      expect(state.volume, 1.0);
    });

    test('uses safe defaults for malformed snapshot values', () {
      final state = Media3PlaybackState.fromMap(<Object?, Object?>{
        'positionMs': 'unknown',
        'volume': double.nan,
        'isPlaying': 'yes',
      });

      expect(state.position, Duration.zero);
      expect(state.volume, 1.0);
      expect(state.isPlaying, isFalse);
      expect(state.mediaId, isNull);
    });
  });
  group('Media3PlaybackClient input validation', () {
    final client = Media3PlaybackClient();

    test('rejects source URIs without a scheme before channel invocation', () async {
      await expectLater(
        client.setSource(Uri.parse('/storage/emulated/0/Music/song.mp3')),
        throwsArgumentError,
      );
    });

    test('rejects negative seek positions before channel invocation', () async {
      await expectLater(
        client.seekTo(const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
    });

    test('rejects non-finite volume before channel invocation', () async {
      await expectLater(client.setVolume(double.nan), throwsArgumentError);
    });

    test('rejects invalid gain factors before channel invocation', () async {
      await expectLater(
        client.setGainFactors(trackLevel: double.nan),
        throwsArgumentError,
      );
      await expectLater(
        client.setGainFactors(preamp: -0.01),
        throwsArgumentError,
      );
      await expectLater(
        client.setGainFactors(focusDuck: 1.01),
        throwsArgumentError,
      );
    });

    test('accepts normalized gain factors without requiring native playback', () async {
      // Validation completes before the platform call; a missing platform
      // implementation is expected only after valid values are accepted.
      await expectLater(
        client.setGainFactors(
          trackLevel: 0.8,
          preamp: 0.7,
          sleepFade: 0.5,
          focusDuck: 1.0,
        ),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('rejects an empty native queue before channel invocation', () async {
      await expectLater(client.setQueue(const <Media3QueueItem>[]), throwsArgumentError);
    });

    test('rejects an out-of-range queue index before channel invocation', () async {
      await expectLater(
        client.setQueue(
          <Media3QueueItem>[
            Media3QueueItem(
              id: 'track-1',
              uri: Uri(scheme: 'file', path: '/music/one.mp3'),
              title: 'One',
            ),
          ],
          startIndex: 1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects repeat modes not supported by Media3 queue policy', () async {
      await expectLater(client.setRepeatMode('random'), throwsArgumentError);
    });

    test('queue item requires a URI scheme', () {
      final item = Media3QueueItem(
        id: 'track-1',
        uri: Uri(path: '/music/one.mp3'),
        title: 'One',
      );
      expect(item.toMap, throwsArgumentError);
    });
  });

}
