import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/services/media3_music_provider_adapter.dart';
import 'package:resonate/services/media3_playback_client.dart';
import 'package:resonate/services/playback_backend.dart';
import 'package:resonate/services/playback_snapshot.dart';

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

  group('PlaybackBackend contract', () {
    test('Media3 adapter implements the shared transport contract', () {
      final PlaybackBackend backend = Media3MusicProviderAdapter(
        client: Media3PlaybackClient(),
      );
      final Stream<PlaybackSnapshot> snapshots = backend.states;
      expect(backend, isA<Media3MusicProviderAdapter>());
      expect(snapshots, isA<Stream<PlaybackSnapshot>>());
    });

    test('repeat policy has explicit backend values', () {
      expect(PlaybackQueueRepeatMode.off.nativeValue, 'off');
      expect(PlaybackQueueRepeatMode.one.nativeValue, 'one');
      expect(PlaybackQueueRepeatMode.all.nativeValue, 'all');
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

    test('rejects an index outside the original queue', () {
      expect(
        () => Media3MusicProviderAdapter.resolvePlayableStartIndex(
          <Song>[song()],
          1,
        ),
        throwsArgumentError,
      );
    });

    test('remaps start index after invalid tracks before selection are filtered', () {
      final queue = <Song>[
        song(id: 'invalid', filePath: ' '),
        song(id: 'first', filePath: '/music/first.mp3'),
        song(id: 'also-invalid', filePath: ''),
        song(id: 'selected', filePath: '/music/selected.mp3'),
      ];

      expect(Media3MusicProviderAdapter.resolvePlayableStartIndex(queue, 3), 1);
    });

    test('rejects selection of an unplayable original queue item', () {
      final queue = <Song>[
        song(id: 'first', filePath: '/music/first.mp3'),
        song(id: 'invalid', filePath: ' '),
        song(id: 'last', filePath: '/music/last.mp3'),
      ];

      expect(
        () => Media3MusicProviderAdapter.resolvePlayableStartIndex(queue, 1),
        throwsArgumentError,
      );
    });

    test('maps native index back to original index when invalid items are filtered', () {
      final queue = <Song>[
        song(id: 'invalid-a', filePath: ''),
        song(id: 'first', filePath: '/music/first.mp3'),
        song(id: 'invalid-b', filePath: ' '),
        song(id: 'second', filePath: '/music/second.mp3'),
      ];

      expect(Media3MusicProviderAdapter.resolveOriginalQueueIndex(queue, 0), 1);
      expect(Media3MusicProviderAdapter.resolveOriginalQueueIndex(queue, 1), 3);
      expect(Media3MusicProviderAdapter.resolveOriginalQueueIndex(queue, 2), isNull);
      expect(Media3MusicProviderAdapter.resolveOriginalQueueIndex(queue, -1), isNull);
    });

    test('resolves current track by stable media ID when index disagrees', () {
      final queue = <Song>[
        song(id: 'first', filePath: '/music/first.mp3'),
        song(id: 'second', filePath: '/music/second.mp3'),
      ];

      expect(
        Media3MusicProviderAdapter.resolveCurrentSong(
          queue,
          mediaId: 'second',
          playableIndex: 0,
        )?.id,
        'second',
      );
      expect(
        Media3MusicProviderAdapter.resolveCurrentQueueIndex(
          queue,
          mediaId: 'second',
          playableIndex: 0,
        ),
        1,
      );
    });

    test('uses native index to distinguish repeated occurrences of the same song', () {
      final repeated = song(id: 'same', filePath: '/music/same.mp3');
      final queue = <Song>[
        repeated,
        song(id: 'middle', filePath: '/music/middle.mp3'),
        repeated,
      ];

      expect(
        Media3MusicProviderAdapter.resolveCurrentQueueIndex(
          queue,
          mediaId: 'same',
          playableIndex: 2,
        ),
        2,
      );
    });

    test('does not guess when duplicate IDs cannot be disambiguated', () {
      final queue = <Song>[
        song(id: 'same', filePath: '/music/one.mp3'),
        song(id: 'same', filePath: '/music/two.mp3'),
      ];

      expect(
        Media3MusicProviderAdapter.resolveCurrentQueueIndex(
          queue,
          mediaId: 'same',
          playableIndex: 10,
        ),
        isNull,
      );
    });

    test('does not fall back to an unrelated index when media ID is stale', () {
      final queue = <Song>[
        song(id: 'first', filePath: '/music/first.mp3'),
        song(id: 'second', filePath: '/music/second.mp3'),
      ];

      expect(
        Media3MusicProviderAdapter.resolveCurrentSong(
          queue,
          mediaId: 'removed-track',
          playableIndex: 1,
        ),
        isNull,
      );
    });

    test('falls back to native queue index only when media ID is unavailable', () {
      final queue = <Song>[
        song(id: 'invalid', filePath: ''),
        song(id: 'first', filePath: '/music/first.mp3'),
        song(id: 'second', filePath: '/music/second.mp3'),
      ];

      expect(
        Media3MusicProviderAdapter.resolveCurrentSong(
          queue,
          mediaId: null,
          playableIndex: 1,
        )?.id,
        'second',
      );
    });

    test('does not resolve a current track from an invalid native index', () {
      expect(
        Media3MusicProviderAdapter.resolveCurrentSong(
          <Song>[song()],
          mediaId: null,
          playableIndex: 10,
        ),
        isNull,
      );
    });
  });
}