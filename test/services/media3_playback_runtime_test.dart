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

class FakePlaybackBackend implements PlaybackBackend, PlaybackCrossfadeBackend {
  final StreamController<PlaybackSnapshot> controller =
      StreamController<PlaybackSnapshot>.broadcast();
  PlaybackSnapshot value = snapshot();
  List<Song> loaded = const [];
  int loadedIndex = -1;
  bool playing = false;
  bool? lastShuffleMode;
  Map<String, double?> lastGainFactors = const {};
  Song? preloadedSong;
  List<Song>? preloadedQueue;
  int? preloadedQueueIndex;
  Duration? crossfadeDuration;
  int cancelCrossfadeCalls = 0;
  Completer<void>? loadGate;
  Completer<PlaybackSnapshot>? stateGate;
  Completer<void>? stateReadStarted;
  bool failLoad = false;
  Completer<void>? pauseGate;
  final List<String> commandOrder = <String>[];

  @override
  Stream<PlaybackSnapshot> get states => controller.stream;
  @override
  Future<PlaybackSnapshot> currentState() async {
    if (!(stateReadStarted?.isCompleted ?? true)) {
      stateReadStarted!.complete();
    }
    final gate = stateGate;
    if (gate != null) return gate.future;
    return value;
  }
  @override
  Future<void> loadQueue(List<Song> songs, {int startIndex = 0}) async {
    await loadGate?.future;
    if (failLoad) throw StateError('simulated queue load failure');
    loaded = List<Song>.of(songs);
    loadedIndex = startIndex;
    value = snapshot(mediaId: songs[startIndex].id, index: startIndex, queueLength: songs.length);
  }
  @override
  Future<void> clearQueue() async {
    commandOrder.add('clearQueue');
    loaded = const <Song>[];
    loadedIndex = -1;
    value = snapshot(mediaId: null, index: -1, queueLength: 0);
  }
  @override
  Future<void> play() async { commandOrder.add('play'); playing = true; }
  @override
  Future<void> pause() async {
    commandOrder.add('pause-start');
    await pauseGate?.future;
    playing = false;
    commandOrder.add('pause-end');
  }
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
  Future<void> setGainFactors({double? trackLevel, double? preamp, double? sleepFade, double? focusDuck}) async {
    lastGainFactors = {'trackLevel': trackLevel, 'preamp': preamp, 'sleepFade': sleepFade, 'focusDuck': focusDuck};
  }
  @override
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode) async {}
  @override
  Future<void> setShuffleMode(bool enabled) async { lastShuffleMode = enabled; }
  @override
  Future<void> preloadNext(Song song, {List<Song>? queue, int? startIndex}) async {
    preloadedSong = song;
    preloadedQueue = queue;
    preloadedQueueIndex = startIndex;
  }
  @override
  Future<void> crossfade({required Duration duration}) async { crossfadeDuration = duration; }
  @override
  Future<void> cancelCrossfade() async { cancelCrossfadeCalls++; }
}

void main() {
  group('Media3PlaybackRuntime', () {
    late FakePlaybackBackend backend;
    late Media3PlaybackRuntime runtime;

    setUp(() async {
      backend = FakePlaybackBackend();
      runtime = Media3PlaybackRuntime(backend);
      await runtime.connect();
    });

    tearDown(() async {
      await runtime.dispose();
      await backend.controller.close();
    });

    test('does not let a delayed initial snapshot overwrite a newer stream event', () async {
      final stale = snapshot(mediaId: 'stale', index: 0);
      final fresh = snapshot(mediaId: 'fresh', index: 1, playing: true);
      backend.value = stale;
      backend.stateGate = Completer<PlaybackSnapshot>();
      backend.stateReadStarted = Completer<void>();

      final freshState = runtime.states.firstWhere(
        (state) => state.snapshot?.mediaId == 'fresh',
      );
      final reconnect = runtime.connect();
      // Wait until connect has installed its backend listener and started the
      // delayed snapshot read before publishing the newer stream event.
      await backend.stateReadStarted!.future;
      backend.controller.add(fresh);
      await freshState;
      backend.stateGate!.complete(stale);
      await reconnect;

      expect(runtime.current.snapshot?.mediaId, 'fresh');
      expect(runtime.current.isPlaying, isTrue);
    });

    test('serializes concurrent reconnects without duplicate state subscriptions', () async {
      final observed = <Media3RuntimeState>[];
      final subscription = runtime.states.listen(observed.add);

      await Future.wait<void>([
        runtime.connect(),
        runtime.connect(),
      ]);
      backend.controller.add(snapshot(mediaId: 'fresh', playing: true));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        observed.where((state) => state.snapshot?.mediaId == 'fresh').length,
        1,
      );
      await subscription.cancel();
    });

    test('does not publish a delayed snapshot after disposal', () async {
      backend.stateGate = Completer<PlaybackSnapshot>();
      backend.stateReadStarted = Completer<void>();

      final reconnect = runtime.connect();
      await backend.stateReadStarted!.future;
      await runtime.dispose();
      backend.stateGate!.complete(snapshot(mediaId: 'late', playing: true));
      await reconnect;

      expect(runtime.current.snapshot?.mediaId, isNot('late'));
    });

    test('clears native and Dart queue identity through the serialized lane', () async {
      await runtime.loadQueue([makeSong('a'), makeSong('b')], startIndex: 1);

      await runtime.clearQueue();

      expect(backend.commandOrder, ['clearQueue']);
      expect(backend.loaded, isEmpty);
      expect(backend.loadedIndex, -1);
      expect(runtime.queue, isEmpty);
      expect(runtime.current.currentSong, isNull);
      expect(runtime.current.currentQueueIndex, isNull);
      expect(runtime.current.isPlaying, isFalse);
    });

    test('preserves committed queue when native clear is rejected', () async {
      await runtime.loadQueue([makeSong('stable')]);
      backend.failLoad = true;
      // Use the backend's load failure switch to simulate a rejected clear.
      final originalClear = backend.clearQueue;
      backend.clearQueue = () async => throw StateError('simulated clear failure');

      await expectLater(runtime.clearQueue(), throwsA(isA<StateError>()));
      expect(runtime.queue.map((song) => song.id), ['stable']);
      expect(runtime.current.currentSong?.id, 'stable');
      backend.clearQueue = originalClear;
    });

    test('loads queue through a single backend without optimistic playing state', () async {
      final songs = [makeSong('a'), makeSong('b')];
      await runtime.loadQueue(songs, startIndex: 1);

      expect(backend.loaded.map((s) => s.id), ['a', 'b']);
      expect(backend.loadedIndex, 1);
      expect(runtime.current.currentSong?.id, 'b');
      expect(runtime.current.currentQueueIndex, 1);
      expect(runtime.current.isPlaying, isFalse);
    });

    test('does not commit a queue when disposed during native load', () async {
      backend.loadGate = Completer<void>();
      final replacement = runtime.loadQueue([makeSong('late')]);
      await Future<void>.delayed(Duration.zero);

      await runtime.dispose();
      backend.loadGate!.complete();

      await expectLater(replacement, throwsA(isA<StateError>()));
      expect(runtime.queue, isEmpty);
      expect(runtime.current.currentSong, isNull);
    });

    test('buffers snapshots until replacement queue identity is committed', () async {
      await runtime.loadQueue([makeSong('old')]);
      final observed = <Media3RuntimeState>[];
      final acceptedState = Completer<void>();
      final subscription = runtime.states.listen((state) {
        observed.add(state);
        if (state.currentSong?.id == 'new' && !acceptedState.isCompleted) {
          acceptedState.complete();
        }
      });
      addTearDown(subscription.cancel);

      backend.loadGate = Completer<void>();
      final replacement = runtime.loadQueue([makeSong('new')]);
      await Future<void>.delayed(Duration.zero);

      // A late event from the outgoing queue must not be published against
      // the old Dart queue while the native queue replacement is in flight.
      backend.controller.add(snapshot(mediaId: 'old', index: 0));
      await Future<void>.delayed(Duration.zero);
      expect(observed, isEmpty);

      backend.loadGate!.complete();
      await replacement;
      // Broadcast stream delivery is asynchronous; wait for the runtime to
      // publish the accepted queue's reconciled state before asserting it.
      await acceptedState.future;

      expect(runtime.queue.map((song) => song.id), ['new']);
      expect(runtime.current.currentSong?.id, 'new');
      expect(observed, isNotEmpty);
      expect(observed.every((state) => state.currentSong?.id != 'old'), isTrue);
    });

    test('does not commit queue identity when the backend rejects a load', () async {
      final original = [makeSong('old')];
      await runtime.loadQueue(original);
      backend.failLoad = true;

      await expectLater(
        runtime.loadQueue([makeSong('new')]),
        throwsA(isA<StateError>()),
      );

      expect(runtime.queue.map((song) => song.id), ['old']);
      expect(backend.loaded.map((song) => song.id), ['old']);
    });

    test('command lane remains usable after a queue load fails', () async {
      await runtime.loadQueue([makeSong('stable')]);
      backend.failLoad = true;

      final failedLoad = runtime.loadQueue([makeSong('rejected')]);
      final playAfterFailure = runtime.play();

      await expectLater(failedLoad, throwsA(isA<StateError>()));
      await playAfterFailure;

      expect(runtime.queue.map((song) => song.id), ['stable']);
      expect(backend.loaded.map((song) => song.id), ['stable']);
      expect(backend.commandOrder, ['play']);
      expect(backend.playing, isTrue);
    });

    test('serializes transport commands in invocation order', () async {
      backend.pauseGate = Completer<void>();
      final pause = runtime.pause();
      final play = runtime.play();
      await Future<void>.delayed(Duration.zero);

      expect(backend.commandOrder, ['pause-start']);
      backend.pauseGate!.complete();
      await Future.wait([pause, play]);
      expect(backend.commandOrder, ['pause-start', 'pause-end', 'play']);
      expect(backend.playing, isTrue);
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

    test('forwards composed gain factors atomically to the backend', () async {
      await runtime.setGainFactors(trackLevel: 0.8, preamp: 0.7, sleepFade: 0.5, focusDuck: 1.0);
      expect(backend.lastGainFactors, {
        'trackLevel': 0.8, 'preamp': 0.7, 'sleepFade': 0.5, 'focusDuck': 1.0,
      });
    });

    test('forwards native preload, crossfade and cancellation to dual-deck backend', () async {
      final incoming = makeSong('incoming');
      await runtime.preloadNext(incoming);
      await runtime.crossfade(duration: const Duration(seconds: 4));
      await runtime.cancelCrossfade();

      expect(backend.preloadedSong?.id, 'incoming');
      expect(backend.crossfadeDuration, const Duration(seconds: 4));
      expect(backend.cancelCrossfadeCalls, 1);
    });

    test('preloads the full queue at the incoming occurrence for seamless handoff', () async {
      final first = makeSong('first');
      final incoming = makeSong('incoming');
      final last = makeSong('last');
      await runtime.loadQueue([first, incoming, last], startIndex: 0);
      await runtime.preloadNext(incoming);

      expect(backend.preloadedSong?.id, 'incoming');
      expect(backend.preloadedQueue?.map((song) => song.id), ['first', 'incoming', 'last']);
      expect(backend.preloadedQueueIndex, 1);
    });

    test('rejects crossfade durations outside native supported range', () async {
      await expectLater(
        runtime.crossfade(duration: const Duration(milliseconds: 100)),
        throwsArgumentError,
      );
      await expectLater(
        runtime.crossfade(duration: const Duration(seconds: 16)),
        throwsArgumentError,
      );
      expect(backend.crossfadeDuration, isNull);
    });

    test('forwards shuffle policy to the backend', () async {
      await runtime.setShuffleMode(true);
      expect(backend.lastShuffleMode, isTrue);
      await runtime.setShuffleMode(false);
      expect(backend.lastShuffleMode, isFalse);
    });

    test('forwards transport commands to the backend', () async {
      await runtime.play();
      expect(backend.playing, isTrue);
      await runtime.pause();
      expect(backend.playing, isFalse);
    });
  });
}
