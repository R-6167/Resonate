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

    test('repeat policy has explicit native values', () {
      expect(PlaybackQueueRepeatMode.off.nativeValue, 'off');
      expect(PlaybackQueueRepeatMode.one.nativeValue, 'one');
      expect(PlaybackQueueRepeatMode.all.nativeValue, 'all');
    });
  });
}
