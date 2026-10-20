import 'package:flutter_test/flutter_test.dart';

import '../../lib/modes/models/media_type.dart';
import '../../lib/modes/services/media_folder_router.dart';

void main() {
  test('selected folders override automatic classification', () {
    final router = MediaFolderRouter({
      MediaType.audiobook: ['/storage/Music/Audiobooks'],
      MediaType.podcast: ['/storage/Podcasts'],
    });

    expect(
      router.typeForPath('/storage/Music/Audiobooks/Book/chapter-01.mp3'),
      MediaType.audiobook,
    );
    expect(
      router.typeForPath('/storage/Podcasts/show/episode-01.mp3'),
      MediaType.podcast,
    );
    expect(router.typeForPath('/storage/Music/song.mp3'), isNull);
  });

  test('the most specific matching folder wins', () {
    final router = MediaFolderRouter({
      MediaType.audiobook: ['/media'],
      MediaType.podcast: ['/media/podcasts'],
    });

    expect(
      router.typeForPath('/media/podcasts/episode.mp3'),
      MediaType.podcast,
    );
    expect(
      router.typeForPath('/media/song.mp3'),
      MediaType.audiobook,
    );
  });

  test('normalizes slashes and trailing separators', () {
    final router = MediaFolderRouter({
      MediaType.motivation: [r'C:\Media\Motivation\'],
    });

    expect(
      router.hasFolder(MediaType.motivation, 'C:/Media/Motivation'),
      isTrue,
    );
    expect(
      router.typeForPath(r'C:\Media\Motivation\speech.mp3'),
      MediaType.motivation,
    );
  });

  test('does not match a similarly named sibling folder', () {
    final router = MediaFolderRouter({
      MediaType.podcast: ['/media/podcast'],
    });

    expect(router.typeForPath('/media/podcasts/episode.mp3'), isNull);
  });
}
