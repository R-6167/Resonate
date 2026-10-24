import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/services/media3_playback_runtime.dart';
import 'package:resonate/services/playback_backend.dart';
import 'package:resonate/services/playback_snapshot.dart';

Song makeSong(String id, {String? path}) => Song(
      id: id,
      title: id,
      artist: 'Artist',
      album: 'Album',
      filePath: path ?? '/music/$id.mp3',
      duration: const Duration(minutes: 3),
      dateAdded: DateTime.utc(2026, 1, 1),
    );

PlaybackSnapshot snapshot({
  String? mediaId,
  int index = 0,
  bool playing = false,
  int queueLength = 1,
}) =>
    PlaybackSnapshot(
      connected: true,
      isPlaying: playing,
      isReady: true,
      playWhenReady: playing,
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 3),
      mediaId: mediaId,
      title: mediaId,
      artist: 'Artist',
      album: 'Album',
      currentQueueIndex: index,
      queueLength: queueLength,
      volume: 1,
      hasError: false,
      error: null,
    );

class FakePlaybackBackend implements PlaybackBackend {
  final StreamController<PlaybackSnapshot> controller =
      StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot value = snapshot();
  List<Song> loaded = const [];
  int loadedIndex = -1;
  bool playing = false;

  @override
  Stream<PlaybackSnapshot> get states => controller.stream;
  @override
  Future<PlaybackSnapshot> currentState() async => value;
  @override
  Future<void> loadQueue(List<Song> songs, {int startIndex = 0}) async {
    loaded = List<Song>.of(songs);
    loadedIndex = startIndex;
    value = snapshot(mediaId: songs[startIndex].id, index: startIndex, queueLength: songs.length);
  }
  @override
  Future<void> play() async { playing = true; }
  @override
  Future<void> pause() async { playing = false; }
  @override
  Future<void> stop() async { playing = false; }
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode) async {}
}

void main() {
  group('Media3PlaybackRuntime', () {
    late FakePlaybackBackend backend;
    late Media3PlaybackRuntime runtime;

    setUp(() {
      backend = FakePlaybackBackend();
      runtime = Media3PlaybackRuntime(backend);
    });

    tearDown(() async {
      await runtime.dispose();
      await backend.controller.close();
    });

    test('loads queue through a single backend without optimistic playing state', () async {
      final songs = [makeSong('a'), makeSong('b')];
      await runtime.loadQueue(songs, startIndex: 1);

      expect(backend.loaded.map((s) => s.id), ['a', 'b']);
      expect(backend.loadedIndex, 1);
      expect(runtime.current.currentSong, isNull);
      expect(runtime.current.isPlaying, isFalse);
    });

    test('rejects invalid and unplayable selected entries before dispatch', () async {
      final songs = [makeSong('a'), makeSong('bad', path: ' '), makeSong('c')];

      await expectLater(runtime.loadQueue(songs, startIndex: 9), throwsArgumentError);
      await expectLater(runtime.loadQueue(songs, startIndex: 1), throwsArgumentError);
      expect(backend.loaded, isEmpty);
    });

    test('reconciles snapshots to the original queue and preserves duplicate occurrence', () async {
      final repeated = makeSong('same');
      await runtime.loadQueue([repeated, makeSong('middle'), repeated]);
      final seen = runtime.states.first;
      backend.controller.add(snapshot(mediaId: 'same', index: 2, queueLength: 3));

      final state = await seen;
      expect(state.currentQueueIndex, 2);
      expect(state.currentSong?.id, 'same');
      expect(state.position, const Duration(seconds: 12));
    });

    test('does not guess a track when native media ID is ambiguous', () async {
      final repeated = makeSong('same');
      await runtime.loadQueue([repeated, makeSong('middle'), repeated]);
      final seen = runtime.states.first;
      backend.controller.add(snapshot(mediaId: 'missing', index: 0, queueLength: 3));

      final state = await seen;
      expect(state.currentQueueIndex, isNull);
      expect(state.currentSong, isNull);
    });

    test('forwards transport commands to the backend', () async {
      await runtime.play();
      expect(backend.playing, isTrue);
      await runtime.pause();
      expect(backend.playing, isFalse);
    });
  });
}
