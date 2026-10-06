import 'package:flutter_test/flutter_test.dart';
import 'package:resonate_modes_lab/modes/models/mode_media_item.dart';

void main() {
  test('mode media item keeps only integration-neutral metadata', () {
    const item = ModeMediaItem(
      id: '1',
      filePath: '/Music/song.mp3',
      title: 'Song',
      album: 'Album',
      artist: 'Artist',
    );
    expect(item.id, '1');
    expect(item.filePath, contains('/Music/'));
  });
}
