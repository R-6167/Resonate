import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/modes/models/media_type.dart';
import 'package:resonate/modes/models/mode_media_item.dart';
import 'package:resonate/modes/services/media_classifier.dart';

void main() {
  test('does not classify a long music mix as audiobook by duration', () {
    const item = ModeMediaItem(
      id: 'mix-1',
      filePath: '/Music/DJ Sets/',
      title: 'Live Mix 01',
      album: 'Night Session',
      artist: 'DJ Example',
    );
    expect(MediaClassifier.instance.classify(item).type, MediaType.music);
  });

  test('folder metadata identifies podcasts', () {
    const item = ModeMediaItem(
      id: 'pod-1',
      filePath: '/Podcasts/Show/',
      title: 'Episode 42',
      artist: 'Host',
    );
    expect(MediaClassifier.instance.classify(item).type, MediaType.podcast);
  });

  test('folder metadata identifies audiobooks', () {
    const item = ModeMediaItem(
      id: 'book-1',
      filePath: '/Audiobooks/Book/',
      title: 'Chapter 7',
      artist: 'Author',
    );
    expect(MediaClassifier.instance.classify(item).type, MediaType.audiobook);
  });
}
