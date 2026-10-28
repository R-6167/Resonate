import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/services/media3_provider_session.dart';
import 'package:resonate/services/playback_backend.dart';
import 'package:resonate/services/playback_snapshot.dart';
import 'package:resonate/services/playback_engine_session.dart';
import 'package:resonate/services/playback_observation_source.dart';

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
  int? audioSessionId,
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
      queueLength: 1,
      volume: 0.75,
      audioSessionId: audioSessionId,
      hasError: false,
      error: null,
    );

class _Backend implements PlaybackBackend, PlaybackCrossfadeBackend {
  final StreamController<PlaybackSnapshot> controller =
      StreamController<PlaybackSnapshot>.broadcast();
  final List<String> calls = <String>[];
  int currentStateCalls = 0;
  PlaybackSnapshot value = _snapshot();

  @override
  Stream<PlaybackSnapshot> get states => controller.stream;
  @override
  Future<PlaybackSnapshot> currentState() async {
    currentStateCalls++;
    return value;
  }
  @override
  Future<void> loadQueue(List<Song> songs, {int startIndex = 0}) async {
    calls.add('loadQueue');
    value = _snapshot(mediaId: songs[startIndex].id, index: startIndex);
    controller.add(value);
  }
  @override
  Future<void> play() async {
    calls.add('play');
    value = _snapshot(mediaId: value.mediaId, playing: true);
    controller.add(value);
  }
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration position) async => calls.add('seek');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> setVolume(double value) async => calls.add('volume');
  @override
  Future<void> setGainFactors({
    double? trackLevel,
    double? preamp,
    double? sleepFade,
    double? focusDuck,
  }) async => calls.add('gain');
  @override
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode) async =>
      calls.add('repeat');
  @override
  Future<void> setShuffleMode(bool enabled) async => calls.add('shuffle');
  @override
  Future<void> preloadNext(
    Song song, {
    List<Song>? queue,
    int? startIndex,
  }) async => calls.add('preloadNext');
  @override
  Future<void> crossfade({required Duration duration}) async =>
      calls.add('crossfade');
  @override
  Future<void> cancelCrossfade() async => calls.add('cancelCrossfade');
}

void main() {
  group('Media3ProviderSession', () {
    late _Backend backend;
    late Media3ProviderSession session;

    setUp(() {
      backend = _Backend();
      session = Media3ProviderSession(backend: backend);
    });

    tearDown(() async {
      await session.dispose();
      await backend.controller.close();
    });

    test('composes runtime and state projection around one backend', () async {
      await session.start();
      await session.start();
      final projectedState = session.states.firstWhere(
        (state) => state.currentSong?.id == 'track-1',
      );
      await session.loadQueue(<Song>[_song('track-1')]);
      final state = await projectedState;

      expect(session.queue.map((song) => song.id), ['track-1']);
      expect(state.currentSong?.id, 'track-1');
      expect(state.isReady, isTrue);
      expect(state.volume, 0.75);
      expect(backend.calls, ['loadQueue']);
    });

    test('coalesces concurrent startup requests into one backend connection', () async {
      await Future.wait<void>([
        session.start(),
        session.start(),
        session.start(),
      ]);

      expect(backend.currentStateCalls, 1);
    });

    test('implements one contract for commands and observations', () async {
      final PlaybackEngineSession engine = session;
      final PlaybackObservationSource observations = engine;
      await engine.start();

      final position = observations.positionStream.firstWhere(
        (value) => value == const Duration(seconds: 12),
      );
      final duration = observations.durationStream.firstWhere(
        (value) => value == const Duration(minutes: 3),
      );
      await engine.loadQueue(<Song>[_song('track-1')]);

      expect(await position, const Duration(seconds: 12));
      expect(await duration, const Duration(minutes: 3));
      expect(engine.queue.map((song) => song.id), ['track-1']);
    });

    test('emits the current session to late DSP subscribers', () async {
      backend.value = _snapshot(mediaId: 'track-1', audioSessionId: 37);
      await session.start();

      final sessions = <int?>[];
      final subscription = session.audioSessionIdStream.listen(sessions.add);
      await Future<void>.delayed(Duration.zero);

      expect(sessions, [37]);
      await subscription.cancel();
    });

    test('publishes audio-session changes for DSP handoff', () async {
      await session.start();
      final sessions = <int?>[];
      final subscription = session.audioSessionIdStream.listen(sessions.add);
      await Future<void>.delayed(Duration.zero);
      sessions.clear();

      backend.value = _snapshot(mediaId: 'track-1', audioSessionId: 37);
      backend.controller.add(backend.value);
      await Future<void>.delayed(Duration.zero);
      backend.value = _snapshot(mediaId: 'track-1', audioSessionId: 42);
      backend.controller.add(backend.value);
      await Future<void>.delayed(Duration.zero);

      expect(sessions, [37, 42]);
      await subscription.cancel();
    });

    test('publishes audio-session loss so DSP can detach safely', () async {
      await session.start();
      backend.value = _snapshot(mediaId: 'track-1', audioSessionId: 37);
      backend.controller.add(backend.value);
      await Future<void>.delayed(Duration.zero);

      final sessions = <int?>[];
      final subscription = session.audioSessionIdStream.listen(sessions.add);
      await Future<void>.delayed(Duration.zero);
      sessions.clear();

      backend.value = _snapshot(mediaId: 'track-1', audioSessionId: null);
      backend.controller.add(backend.value);
      await Future<void>.delayed(Duration.zero);

      expect(sessions, [null]);
      await subscription.cancel();
    });

    test('forwards transport through the serialized runtime', () async {
      await session.start();
      await session.loadQueue(<Song>[_song('track-1')]);
      await Future.wait<void>([
        session.play(),
        session.setRepeatMode(PlaybackQueueRepeatMode.all),
        session.setShuffleMode(true),
        session.setGainFactors(preamp: 1.1),
        session.seek(const Duration(seconds: 20)),
      ]);

      expect(backend.calls, [
        'loadQueue',
        'play',
        'repeat',
        'shuffle',
        'gain',
        'seek',
      ]);
    });

    test('forwards the full transport and crossfade contract through one session', () async {
      await session.start();
      final queue = <Song>[_song('track-1'), _song('track-2')];
      await session.loadQueue(queue);
      await session.play();
      await session.pause();
      await session.seek(const Duration(seconds: 20));
      await session.next();
      await session.previous();
      await session.setVolume(0.8);
      await session.setGainFactors(
        trackLevel: 0.9,
        preamp: 1.1,
        sleepFade: 0.7,
        focusDuck: 0.5,
      );
      await session.setRepeatMode(PlaybackQueueRepeatMode.one);
      await session.setShuffleMode(true);
      await session.preloadNext(queue[1], queueIndex: 1);
      await session.crossfade(duration: const Duration(milliseconds: 1200));
      await session.cancelCrossfade();
      await session.stop();

      expect(backend.calls, [
        'loadQueue',
        'play',
        'pause',
        'seek',
        'next',
        'previous',
        'volume',
        'gain',
        'repeat',
        'shuffle',
        'preloadNext',
        'crossfade',
        'cancelCrossfade',
        'stop',
      ]);
    });

    test('dispose prevents later startup and commands', () async {
      await session.dispose();
      await expectLater(session.start(), throwsStateError);
      expect(() => session.play(), throwsStateError);
    });
  });
}
