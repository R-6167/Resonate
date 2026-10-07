import 'package:flutter_test/flutter_test.dart';

import 'package:resonate/models/song.dart';
import 'package:resonate/modes/models/media_type.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/providers/mode_provider.dart';
import 'package:resonate/modes/services/mode_content_resolver.dart';

Song _song(String id) => Song(
  id: id,
  title: id,
  artist: 'Artist',
  album: 'Album',
  filePath: '/music/$id.mp3',
  duration: const Duration(minutes: 3),
  dateAdded: DateTime(2026, 1, 1),
);

void main() {
  test('normal mode leaves generated content unchanged', () {
    final modes = ModeProvider();
    final songs = [_song('a'), _song('b')];
    final resolved = const ModeContentResolver().resolve(
      modes: modes,
      songs: songs,
    );
    expect(resolved.map((s) => s.id), ['a', 'b']);
  });

  test('active mode removes disallowed generated content', () async {
    final modes = ModeProvider();
    await modes.ready;
    await modes.setMode(ResonateMode.running);
    await modes.setUserMediaType(
      _song('podcast'),
      MediaType.podcast,
    );
    await modes.setUserMediaType(
      _song('music'),
      MediaType.music,
    );

    final resolved = const ModeContentResolver().resolve(
      modes: modes,
      songs: [_song('podcast'), _song('music')],
      preferPreferredContent: false,
    );

    expect(resolved.map((s) => s.id), ['music']);
  });

  test('resolver caps results without changing source list', () async {
    final modes = ModeProvider();
    await modes.ready;
    await modes.setMode(ResonateMode.running);
    final songs = [_song('a'), _song('b'), _song('c')];

    final resolved = const ModeContentResolver().resolve(
      modes: modes,
      songs: songs,
      limit: 2,
    );

    expect(resolved.length, 2);
    expect(songs.length, 3);
  });
}
