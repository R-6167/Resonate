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
        'audioSessionId': 37,
        'repeatMode': 'all',
        'shuffleModeEnabled': true,
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
      expect(state.audioSessionId, 37);
      expect(state.repeatMode, 'all');
      expect(state.shuffleModeEnabled, isTrue);
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

    test('uses safe defaults for non-finite native numeric fields', () {
      final state = Media3PlaybackState.fromMap(<Object?, Object?>{
        'positionMs': double.infinity,
        'durationMs': double.infinity,
        'playbackState': double.nan,
        'currentMediaItemIndex': double.infinity,
        'mediaItemCount': double.nan,
        'audioSessionId': double.infinity,
      });

      expect(state.position, Duration.zero);
      expect(state.duration, isNull);
      expect(state.playbackState, 0);
      expect(state.currentMediaItemIndex, -1);
      expect(state.mediaItemCount, 0);
      expect(state.audioSessionId, isNull);
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
      expect(state.audioSessionId, isNull);
      expect(state.repeatMode, 'off');
      expect(state.shuffleModeEnabled, isFalse);
    });
  });
  group('Media3PlaybackClient native acknowledgements', () {
    const channel = MethodChannel('resonate/media3_test_ack');
    late Media3PlaybackClient client;

    setUp(() {
      client = Media3PlaybackClient(methodChannel: channel);
    });

    tearDown(() {
      channel.setMockMethodCallHandler(null);
    });

    test('rejects a queue command explicitly refused by native Media3', () async {
      channel.setMockMethodCallHandler((call) async => false);

      await expectLater(
        client.setQueue(
          <Media3QueueItem>[
            Media3QueueItem(
              id: 'track-1',
              uri: Uri.file('/music/one.mp3'),
              title: 'One',
            ),
          ],
        ),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'MEDIA3_COMMAND_REJECTED',
          ),
        ),
      );
    });

    test('rejects a volume command when native gain policy declines it', () async {
      channel.setMockMethodCallHandler((call) async => false);

      await expectLater(
        client.setVolume(0.5),
        throwsA(isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'MEDIA3_COMMAND_REJECTED',
        )),
      );
    });

    test('does not report crossfade cancellation success when service refuses', () async {
      channel.setMockMethodCallHandler((call) async => false);

      await expectLater(
        client.cancelCrossfade(),
        throwsA(isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'MEDIA3_COMMAND_REJECTED',
        )),
      );
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
        client.setGainFactors(preamp: 4.01),
        throwsArgumentError,
      );
      await expectLater(
        client.setGainFactors(focusDuck: 1.01),
        throwsArgumentError,
      );
    });

    test('accepts positive preamp boost up to 4x without requiring native playback', () async {
      await expectLater(
        client.setGainFactors(trackLevel: 0.25, preamp: 2.0),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('validates shuffle mode and reaches the platform channel', () async {
      await expectLater(
        client.setShuffleMode(true),
        throwsA(isA<MissingPluginException>()),
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
