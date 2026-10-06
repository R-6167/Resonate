import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/modes/models/media_type.dart';
import '../../lib/modes/models/mode_media_item.dart';
import '../../lib/modes/providers/mode_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ModeMediaItem item(String id, String path) => ModeMediaItem(
        id: id,
        filePath: path,
        title: 'Unknown',
        album: '',
        artist: '',
      );

  test('selected folder wins over automatic classification', () async {
    final provider = ModeProvider();
    await provider.ready;

    await provider.addMediaFolder(
      MediaType.audiobook,
      '/storage/Books',
    );

    final result = provider.classificationFor(
      item('book-1', '/storage/Books/long-audio.mp3'),
    );

    expect(result.type, MediaType.audiobook);
    expect(result.source.name, 'user');
    expect(result.confidence, 1.0);
    provider.dispose();
  });

  test('individual user override remains stronger than folder assignment', () async {
    final provider = ModeProvider();
    await provider.ready;

    final media = item('speech-1', '/storage/Audiobooks/speech.mp3');
    await provider.addMediaFolder(MediaType.audiobook, '/storage/Audiobooks');
    await provider.setUserMediaType(media, MediaType.motivation);

    expect(provider.mediaTypeFor(media), MediaType.motivation);
    provider.dispose();
  });

  test('without selected folders automatic classification remains unchanged', () async {
    final provider = ModeProvider();
    await provider.ready;

    final result = provider.classificationFor(
      item('pod-1', '/storage/Podcasts/show.mp3'),
    );

    expect(result.type, MediaType.podcast);
    expect(result.source.name, 'automatic');
    provider.dispose();
  });
}
