import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/services/audio_service_handler.dart';

Song _song(String id, {String? path}) => Song(
      id: id,
      title: id,
      artist: 'Resonate Artist',
      album: 'Resonate Album',
      filePath: path ?? '/music/$id.mp3',
      duration: const Duration(minutes: 3),
      dateAdded: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('AudioServiceHandler queue index mapping', () {
    test('setSongQueue maps original index after unplayable entries', () async {
      final handler = AudioServiceHandler();
      final songs = <Song>[
        _song('first'),
        _song('missing', path: '  '),
        _song('third'),
      ];

      await handler.setSongQueue(songs, startIndex: 2);

      expect(handler.queue.value.map((item) => item.id), ['first', 'third']);
      expect(handler.mediaItem.value?.id, 'third');
    });

    test('publishPlayback keeps system media item aligned with original index',
        () {
      final handler = AudioServiceHandler();
      final songs = <Song>[
        _song('first'),
        _song('missing', path: '  '),
        _song('third'),
      ];

      handler.publishPlayback(
        song: songs[2],
        playing: true,
        position: const Duration(seconds: 12),
        duration: songs[2].duration,
        speed: 1,
        playbackQueue: songs,
        queueIndex: 2,
      );

      expect(handler.queue.value.map((item) => item.id), ['first', 'third']);
      expect(handler.mediaItem.value?.id, 'third');
      expect(handler.playbackState.value.queueIndex, 1);
    });
  });
}
