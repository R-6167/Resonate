import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/modes/models/media_type.dart';
import '../../lib/modes/services/media_folder_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('folder assignments persist independently by content type', () async {
    final store = MediaFolderStore();

    await store.addFolder(MediaType.podcast, '/media/Podcasts/');
    await store.addFolder(MediaType.audiobook, '/media/Books');

    final loaded = await store.loadAll();

    expect(loaded[MediaType.podcast], ['/media/Podcasts']);
    expect(loaded[MediaType.audiobook], ['/media/Books']);
    expect(loaded[MediaType.motivation], isEmpty);
  });

  test('duplicate folders are stored only once', () async {
    final store = MediaFolderStore();

    await store.addFolder(MediaType.motivation, r'C:\Motivation\');
    await store.addFolder(MediaType.motivation, 'C:/Motivation');

    expect(
      (await store.loadAll())[MediaType.motivation],
      ['C:/Motivation'],
    );
  });

  test('unsupported types cannot create folder assignments', () async {
    final store = MediaFolderStore();

    await store.addFolder(MediaType.music, '/media/Music');

    expect((await store.loadAll())[MediaType.music], isEmpty);
  });

  test('folders can be removed or cleared', () async {
    final store = MediaFolderStore();

    await store.addFolder(MediaType.podcast, '/podcasts');
    await store.addFolder(MediaType.podcast, '/podcasts-2');
    await store.removeFolder(MediaType.podcast, '/podcasts');

    expect((await store.loadAll())[MediaType.podcast], ['/podcasts-2']);

    await store.clearFolders(MediaType.podcast);
    expect((await store.loadAll())[MediaType.podcast], isEmpty);
  });
}
