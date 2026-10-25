import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/services/media3_playback_runtime.dart';
import 'package:resonate/services/media3_provider_state_bridge.dart';
import 'package:resonate/services/playback_backend.dart';
import 'package:resonate/services/playback_snapshot.dart';

Song _song(String id) => Song(
      id: id,
      title: id,
      artist: 'Artist',
      album: 'Album',
      filePath: '/music/$id.mp3',
      duration: const Duration(minutes: 3),
      dateAdded: DateTime.utc(2026, 1, 1),
    );

PlaybackSnapshot _snapshot({
  String? mediaId,
  int index = 0,
  bool playing = false,
}) =>
    PlaybackSnapshot(
      connected: true,
      isPlaying: playing,
      isReady: true,
      playWhenReady: playing,
      position: const Duration(seconds: 18),
      duration: const Duration(minutes: 3),
      mediaId: mediaId,
      title: mediaId,
      artist: 'Artist',
      album: 'Album',
      currentQueueIndex: index,
      queueLength: 1,
      volume: 1,
      hasError: false,
      error: null,
    );

class _Backend implements PlaybackBackend {
  final StreamController<PlaybackSnapshot> controller =
      StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot value = _snapshot();

  @override
  Stream<PlaybackSnapshot> get states => controller.stream;
  @override
  Future<PlaybackSnapshot> currentState() async => value;
  @override
  Future<void> loadQueue(List<Song> songs, {int startIndex = 0}) async {
    value = _snapshot(mediaId: songs[startIndex].id, index: startIndex);
  }
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<void> setGainFactors({
    double? trackLevel,
    double? preamp,
    double? sleepFade,
    double? focusDuck,
  }) async {}
  @override
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode) async {}
  @override
  Future<void> setShuffleMode(bool enabled) async {}
}

void main() {
  group('Media3ProviderStateBridge', () {
    late _Backend backend;
    late Media3PlaybackRuntime runtime;
    late Media3ProviderStateBridge bridge;

    setUp(() async {
      backend = _Backend();
      runtime = Media3PlaybackRuntime(backend);
      await runtime.connect();
      bridge = Media3ProviderStateBridge(runtime);
    });

    tearDown(() async {
      await bridge.dispose();
      await runtime.dispose();
      await backend.controller.close();
    });

    test('projects reconciled Media3 state without optimistic changes', () async {
      await runtime.loadQueue([_song('track-1')]);
      await bridge.start();

      expect(bridge.current.currentSong?.id, 'track-1');
      expect(bridge.current.queueIndex, 0);
      expect(bridge.current.isPlaying, isFalse);
      expect(bridge.current.position, const Duration(seconds: 18));
      expect(bridge.current.connected, isTrue);
    });

    test('forwards later native state updates', () async {
      await runtime.loadQueue([_song('track-1')]);
      await bridge.start();

      final nextState = bridge.states.first;
      backend.controller.add(_snapshot(mediaId: 'track-1', playing: true));

      final projected = await nextState;
      expect(projected.currentSong?.id, 'track-1');
      expect(projected.isPlaying, isTrue);
      expect(projected.position, const Duration(seconds: 18));
    });

    test('start is idempotent and disposal stops projection', () async {
      await bridge.start();
      await bridge.start();

      final first = bridge.states.first;
      backend.controller.add(_snapshot(mediaId: 'track-1', playing: true));
      expect((await first).isPlaying, isTrue);

      await bridge.dispose();
      await expectLater(bridge.start(), throwsStateError);
    });
  });
}
