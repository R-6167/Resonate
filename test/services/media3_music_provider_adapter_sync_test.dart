import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/services/media3_music_provider_adapter.dart';
import 'package:resonate/services/media3_playback_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('resonate/media3_adapter_sync_test');
  late Media3MusicProviderAdapter adapter;

  Song song(String id, String path) => Song(
        id: id,
        title: id,
        artist: 'Artist',
        album: 'Album',
        filePath: path,
        duration: const Duration(minutes: 3),
        dateAdded: DateTime.utc(2026, 1, 1),
      );

  setUp(() {
    adapter = Media3MusicProviderAdapter(
      client: Media3PlaybackClient(methodChannel: channel),
    );
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('uses native in-place synchronization for playable queue edits', () async {
    MethodCall? captured;
    channel.setMockMethodCallHandler((call) async {
      captured = call;
      return true;
    });

    await adapter.synchronizeQueue(<Song>[
      song('one', '/music/one.mp3'),
      song('two', '/music/two.mp3'),
    ]);

    expect(captured?.method, 'synchronizeQueue');
    final arguments = Map<Object?, Object?>.from(captured!.arguments as Map);
    final items = arguments['items'] as List<Object?>;
    expect(items, hasLength(2));
    expect((items[1] as Map<Object?, Object?>)['id'], 'two');
  });

  test('filters unplayable queue entries before native synchronization', () async {
    MethodCall? captured;
    channel.setMockMethodCallHandler((call) async {
      captured = call;
      return true;
    });

    await adapter.synchronizeQueue(<Song>[
      song('one', '/music/one.mp3'),
      song('unplayable', '  '),
      song('two', '/music/two.mp3'),
    ]);

    expect(captured?.method, 'synchronizeQueue');
    final arguments = Map<Object?, Object?>.from(captured!.arguments as Map);
    final items = arguments['items'] as List<Object?>;
    expect(items, hasLength(2));
    expect(items.map((item) => (item as Map<Object?, Object?>)['id']),
        <String>['one', 'two']);
  });

  test('clears native queue when no playable items remain', () async {
    MethodCall? captured;
    channel.setMockMethodCallHandler((call) async {
      captured = call;
      return true;
    });

    await adapter.synchronizeQueue(<Song>[song('unplayable', '')]);

    expect(captured?.method, 'clearQueue');
  });
}
