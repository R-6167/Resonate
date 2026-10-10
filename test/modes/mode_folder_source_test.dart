import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/models/song.dart';
import '../../lib/modes/integration/mode_media_source_port.dart';
import '../../lib/modes/models/media_type.dart';
import '../../lib/modes/models/mode_media_item.dart';
import '../../lib/modes/models/resonate_mode.dart';
import '../../lib/modes/providers/mode_provider.dart';

class _FakeModeMediaSource implements ModeMediaSourcePort {
  _FakeModeMediaSource(this.byFolder);

  final Map<String, List<Song>> byFolder;

  @override
  Future<List<Song>> scanFolder(String folderUri) async =>
      byFolder[folderUri] ?? const <Song>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('selected mode folder is scanned and its tracks classify by mode', () async {
    const folder =
        'content://com.android.externalstorage.documents/tree/primary%3AAudiobooks';
    final song = Song(
      id: 'content://media/external/audio/media/123',
      title: 'Chapter 1',
      artist: 'Narrator',
      album: 'Audiobook',
      filePath: 'content://media/external/audio/media/123',
      duration: const Duration(minutes: 12),
      dateAdded: DateTime(2026, 1, 1),
      albumArt: null,
    );
    final modes = ModeProvider()
      ..attachMediaSource(_FakeModeMediaSource(<String, List<Song>>{
        folder: <Song>[song],
      }));
    await modes.ready;
    await modes.setMode(ResonateMode.audiobook);
    await modes.addMediaFolder(MediaType.audiobook, folder);

    expect(
      modes.folderSongsFor(<MediaType>[MediaType.audiobook]).map((s) => s.id),
      <String>[song.id],
    );
    expect(
      modes.mediaTypeFor(ModeMediaItem(
        id: song.id,
        filePath: song.filePath,
        title: song.title,
        album: song.album,
        artist: song.artist,
      )),
      MediaType.audiobook,
    );
    expect(modes.isModeFolderSong(song.id), isTrue);
  });
}
