import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/services/media3_music_provider_adapter.dart';
import 'package:resonate/services/media3_playback_client.dart';
import 'package:resonate/services/playback_backend.dart';

Song song({
  String id = 'track-1',
  String filePath = '/storage/emulated/0/Music/one song.mp3',
  String? albumArt,
}) =>
    Song(
      id: id,
      title: 'One',
      artist: 'Resonate Artist',
      album: 'Resonate Album',
      filePath: filePath,
      duration: const Duration(minutes: 3),
      dateAdded: DateTime.utc(2026, 1, 1),
      albumArt: albumArt,
    );

void main() {
  group('Media3QueueItem.fromSong', () {
    test('maps song metadata and absolute paths to file URIs', () {
      final item = Media3QueueItem.fromSong(song());

      expect(item.id, 'track-1');
      expect(item.title, 'One');
      expect(item.artist, 'Resonate Artist');
      expect(item.album, 'Resonate Album');
      expect(item.uri.scheme, 'file');
      // Uri.path is percent-encoded for spaces; toFilePath returns the
      // filesystem path that the native Media3 source should resolve.
      expect(item.uri.toFilePath(), '/storage/emulated/0/Music/one song.mp3');
    });

    test('preserves content URIs for Android MediaStore items', () {
      final item = Media3QueueItem.fromSong(
        song(filePath: 'content://media/external/audio/media/42'),
      );

      expect(item.uri.scheme, 'content');
      expect(item.uri.toString(), 'content://media/external/audio/media/42');
    });

    test('maps artwork paths and preserves artwork content URIs', () {
      final local = Media3QueueItem.fromSong(song(albumArt: '/storage/art/cover.jpg'));
      final content = Media3QueueItem.fromSong(song(
        albumArt: 'content://media/external/images/media/9',
      ));

      expect(local.artworkUri?.scheme, 'file');
      expect(content.artworkUri?.scheme, 'content');
    });

    test('rejects songs without a playable path', () {
      expect(
        () => Media3QueueItem.fromSong(song(filePath: '  ')),
        throwsArgumentError,
      );
    });
  });

  group('Media3MusicProviderAdapter', () {
    test('rejects a queue containing no playable tracks', () async {
      final adapter = Media3MusicProviderAdapter(
        client: Media3PlaybackClient(),
      );
      await expectLater(
        adapter.loadQueue(<Song>[song(filePath: '  ')]),
        throwsArgumentError,
      );
    });

    test('rejects an index outside the playable queue', () async {
      final adapter = Media3MusicProviderAdapter(
        client: Media3PlaybackClient(),
      );
      await expectLater(
        adapter.loadQueue(<Song>[song()], startIndex: 1),
        throwsArgumentError,
      );
    });

    test('maps original queue indices around unplayable entries', () {
      final songs = <Song>[
        song(id: 'first'),
        song(id: 'unavailable', filePath: '  '),
        song(id: 'third', filePath: '/music/third.mp3'),
      ];

      expect(
        Media3MusicProviderAdapter.resolvePlayableStartIndex(songs, 2),
        1,
      );
      expect(
        Media3MusicProviderAdapter.resolveCurrentQueueIndex(
          songs,
          mediaId: 'third',
          playableIndex: 1,
        ),
        2,
      );
    });

    test('does not guess duplicate queue occurrences when native ID conflicts', () {
      final repeated = song(id: 'duplicate');
      final songs = <Song>[
        repeated,
        song(id: 'middle', filePath: '/music/middle.mp3'),
        repeated,
      ];

      expect(
        Media3MusicProviderAdapter.resolveCurrentQueueIndex(
          songs,
          mediaId: 'missing',
          playableIndex: 0,
        ),
        isNull,
      );
    });

    test('forwards queue, transport policy, and gain updates to native Media3', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('test.resonate/media3');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final adapter = Media3MusicProviderAdapter(
        client: Media3PlaybackClient(methodChannel: channel),
      );
      await adapter.loadQueue(<Song>[
        song(id: 'first'),
        song(id: 'unavailable', filePath: ' '),
        song(id: 'third', filePath: '/music/third.mp3'),
      ], startIndex: 2);
      await adapter.setRepeatMode(PlaybackQueueRepeatMode.all);
      await adapter.setShuffleMode(true);
      await adapter.setGainFactors(
        trackLevel: 0.8,
        preamp: 1.2,
        sleepFade: 0.9,
        focusDuck: 0.5,
      );
      await adapter.seek(const Duration(seconds: 17));
      await adapter.next();

      expect(calls.map((call) => call.method), [
        'setQueue',
        'setRepeatMode',
        'setShuffleMode',
        'setGainFactors',
        'seekTo',
        'skipToNext',
      ]);
      final queueArgs = calls.first.arguments as Map<Object?, Object?>;
      final items = queueArgs['items'] as List<Object?>;
      expect(queueArgs['startIndex'], 1);
      expect(items, hasLength(2));
      expect((items[1] as Map<Object?, Object?>)['id'], 'third');
      expect(calls[1].arguments, {'mode': 'all'});
      expect(calls[2].arguments, {'enabled': true});
      expect(calls[3].arguments, {
        'trackLevel': 0.8,
        'preamp': 1.2,
        'sleepFade': 0.9,
        'focusDuck': 0.5,
      });
      expect(calls[4].arguments, {'positionMs': 17000});
    });

    test('repeat policy has explicit native values', () {
      expect(PlaybackQueueRepeatMode.off.nativeValue, 'off');
      expect(PlaybackQueueRepeatMode.one.nativeValue, 'one');
      expect(PlaybackQueueRepeatMode.all.nativeValue, 'all');
    });
  });
}
