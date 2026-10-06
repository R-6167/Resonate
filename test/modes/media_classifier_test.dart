import 'package:flutter_test/flutter_test.dart';
import 'package:resonate_modes_lab/modes/models/media_type.dart';
import 'package:resonate_modes_lab/modes/models/mode_media_item.dart';
import 'package:resonate_modes_lab/modes/services/media_classifier.dart';

void main() {
  const classifier = MediaClassifier.instance;

  test('long DJ/music mix remains music', () {
    const item = ModeMediaItem(
      id: 'mix-1', filePath: '/Music/DJ Sets/',
      title: 'Live Mix 01', album: 'Night Session', artist: 'DJ Example',
    );
    final result = classifier.classify(item);
    expect(result.type, MediaType.music);
    expect(result.confidence, greaterThanOrEqualTo(.80));
  });

  test('episode word alone in a normal music filename is not a path classification', () {
    const item = ModeMediaItem(
      id: 'song-1', filePath: '/Music/',
      title: 'Episode Zero', artist: 'Band',
    );
    expect(classifier.classify(item).type, MediaType.podcast);
  });

  test('podcast folder identifies podcast', () {
    const item = ModeMediaItem(
      id: 'pod-1', filePath: '/Podcasts/Show/',
      title: '42', artist: 'Host',
    );
    expect(classifier.classify(item).type, MediaType.podcast);
  });

  test('audiobook folder identifies audiobook', () {
    const item = ModeMediaItem(
      id: 'book-1', filePath: '/Audiobooks/Book/',
      title: 'Chapter 7', artist: 'Author',
    );
    expect(classifier.classify(item).type, MediaType.audiobook);
  });

  test('sparse metadata remains unknown', () {
    const item = ModeMediaItem(
      id: 'unknown-1', filePath: '/Media/',
      title: '', artist: '', album: '',
    );
    expect(classifier.classify(item).type, MediaType.unknown);
  });
}
