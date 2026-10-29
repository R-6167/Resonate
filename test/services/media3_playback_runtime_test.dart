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
  Duration? lastSeek;
  double? lastVolume;
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
  bool failClear = false;
  Completer<void>? clearGate;
  Completer<void>? pauseGate;
  final List<String> commandOrder = <String>[];
  bool recordLoadCommands = false;

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
    if (recordLoadCommands) commandOrder.add('loadQueue-start');
    await loadGate?.future;
    if (failLoad) throw StateError('simulated queue load failure');
    loaded = List<Song>.of(songs);
    loadedIndex = startIndex;
    value = snapshot(mediaId: songs[startIndex].id, index: startIndex, queueLength: songs.length);
    if (recordLoadCommands) commandOrder.add('loadQueue-end');
  }
  @override
  Future<void> clearQueue() async {
    commandOrder.add('clearQueue');
    await clearGate?.future;
    if (failClear) throw StateError('simulated clear failure');
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
  Future<void> seek(Duration position) async { commandOrder.add('seek'); lastSeek = position; }
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> setVolume(double value) async { lastVolume = value; }
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

    test('queue clear waits behind an in-flight transport command', () async {
      await runtime.loadQueue([makeSong('stable')]);
      backend.pauseGate = Completer<void>();

      final pause = runtime.pause();
      final clear = runtime.clearQueue();
      await Future<void>.delayed(Duration.zero);

      expect(backend.commandOrder, ['pause-start']);
      expect(backend.loaded.map((song) => song.id), ['stable']);
      expect(runtime.queue.map((song) => song.id), ['stable']);

      backend.pauseGate!.complete();
      await Future.wait([pause, clear]);

      expect(backend.commandOrder, ['pause-start', 'pause-end', 'clearQueue']);
      expect(backend.loaded, isEmpty);
      expect(runtime.queue, isEmpty);
    });

    test('does not let a delayed clear snapshot overwrite a newer native event', () async {
      await runtime.loadQueue([makeSong('old')]);

      final stale = snapshot(mediaId: 'stale', playing: false, queueLength: 0);
      final fresh = snapshot(mediaId: 'fresh', playing: true, queueLength: 0);
      backend.stateGate = Completer<PlaybackSnapshot>();
      backend.stateReadStarted = Completer<void>();

      final clear = runtime.clearQueue();
      await backend.stateReadStarted!.future;
      final freshState = runtime.states.firstWhere(
        (state) => state.snapshot?.mediaId == 'fresh',
      );
      backend.value = fresh;
      backend.controller.add(fresh);
      await freshState;
      backend.stateGate!.complete(stale);
      await clear;

      expect(runtime.queue, isEmpty);
      expect(runtime.current.snapshot?.mediaId, 'fresh');
      expect(runtime.current.isPlaying, isTrue);
    });

    test('preserves committed queue when native clear is rejected', () async {
      await runtime.loadQueue([makeSong('stable')]);
      backend.failClear = true;

      await expectLater(runtime.clearQueue(), throwsA(isA<StateError>()));
      expect(runtime.queue.map((song) => song.id), ['stable']);
      expect(runtime.current.currentSong?.id, 'stable');
    });

    test('ignores a partial empty snapshot when native clear is rejected', () async {
      await runtime.loadQueue([makeSong('stable')]);
      backend.failClear = true;
      backend.clearGate = Completer<void>();

      final clear = runtime.clearQueue();
      await Future<void>.delayed(Duration.zero);
      backend.controller.add(snapshot(mediaId: null, index: -1, queueLength: 0));
      await Future<void>.delayed(Duration.zero);
      backend.clearGate!.complete();

      await expectLater(clear, throwsA(isA<StateError>()));
      expect(runtime.queue.map((song) => song.id), ['stable']);
      expect(runtime.current.currentSong?.id, 'stable');
      expect(runtime.current.snapshot?.mediaId, 'stable');
    });

    test('command lane remains usable after native clear is rejected', () async {
      await runtime.loadQueue([makeSong('stable')]);
      backend.failClear = true;

      await expectLater(
        runtime.clearQueue(),
        throwsA(isA<StateError>()),
      );
      await runtime.play();

      expect(runtime.queue.map((song) => song.id), ['stable']);
      expect(runtime.current.currentSong?.id, 'stable');
      expect(backend.loaded.map((song) => song.id), ['stable']);
      expect(backend.commandOrder, ['clearQueue', 'play']);
      expect(backend.playing, isTrue);
    });

    test('ignores an uncommitted native snapshot when queue replacement fails', () async {
      await runtime.loadQueue([makeSong('stable')]);
      backend.loadGate = Completer<void>();
      backend.failLoad = true;

      final replacement = runtime.loadQueue([makeSong('rejected')]);
      await Future<void>.delayed(Duration.zero);
      backend.controller.add(snapshot(mediaId: 'rejected', index: 0));
      await Future<void>.delayed(Duration.zero);
      backend.loadGate!.complete();

      await expectLater(replacement, throwsA(isA<StateError>()));
      expect(runtime.queue.map((song) => song.id), ['stable']);
      expect(runtime.current.currentSong?.id, 'stable');
      expect(runtime.current.snapshot?.mediaId, 'stable');
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

    test('does not reload or cancel preload for an unchanged queue', () async {
      final songs = [makeSong('a'), makeSong('b')];
      await runtime.loadQueue(songs, startIndex: 1);
      backend.preloadedSong = songs[0];

      await runtime.synchronizeQueue([
        makeSong('a'),
        makeSong('b'),
      ]);

      expect(backend.loaded.map((song) => song.id), ['a', 'b']);
      expect(backend.loadedIndex, 1);
      expect(backend.cancelCrossfadeCalls, 0);
      expect(backend.preloadedSong?.id, 'a');
      expect(backend.commandOrder, isEmpty);
      expect(runtime.current.currentSong?.id, 'b');
      expect(runtime.current.currentQueueIndex, 1);
    });

    test('reloads queue when metadata changes despite stable track identity', () async {
      final original = makeSong('a');
      await runtime.loadQueue([original]);
      final updated = Song(
        id: original.id,
        title: 'Updated title',
        artist: original.artist,
        album: original.album,
        filePath: original.filePath,
        duration: original.duration,
        dateAdded: original.dateAdded,
        albumArt: original.albumArt,
      );

      await runtime.synchronizeQueue([updated]);

      expect(backend.loaded.single.title, 'Updated title');
      expect(backend.cancelCrossfadeCalls, 1);
      expect(backend.commandOrder, ['seek', 'pause-start', 'pause-end']);
    });

    test('validates gain factors before sending native commands', () async {
      expect(
        () => runtime.setGainFactors(trackLevel: double.nan),
        throwsArgumentError,
      );
      expect(
        () => runtime.setGainFactors(preamp: 4.01),
        throwsArgumentError,
      );
      expect(
        () => runtime.setGainFactors(focusDuck: -0.1),
        throwsArgumentError,
      );
      expect(() => runtime.setVolume(double.infinity), throwsArgumentError);
      expect(backend.commandOrder, isEmpty);
      expect(backend.lastGainFactors, isEmpty);
    });

    test('clamps master volume at the runtime boundary', () async {
      await runtime.setVolume(1.5);
      expect(backend.commandOrder, isEmpty);
      // The fake records gain commands separately; assert the backend saw the
      // normalized volume via a dedicated value rather than relying on native
      // channel validation.
      expect(backend.lastVolume, 1.0);
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

    test('rejects explicit preload indices that do not identify the incoming song', () async {
      final first = makeSong('first');
      final incoming = makeSong('incoming');
      final last = makeSong('last');
      await runtime.loadQueue([first, incoming, last]);

      await expectLater(
        runtime.preloadNext(incoming, queueIndex: 2),
        throwsArgumentError,
      );
      await expectLater(
        runtime.preloadNext(incoming, queueIndex: 8),
        throwsArgumentError,
      );

      expect(backend.preloadedSong, isNull);
      expect(backend.preloadedQueueIndex, isNull);
    });

    test('rejects an explicit preload index when no queue is committed', () async {
      await expectLater(
        runtime.preloadNext(makeSong('incoming'), queueIndex: 0),
        throwsArgumentError,
      );
      expect(backend.preloadedSong, isNull);
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

    test('synchronizes a live queue edit while retaining current track, position and play intent', () async {
      final first = makeSong('first');
      final current = makeSong('current');
      final last = makeSong('last');
      await runtime.loadQueue([first, current, last], startIndex: 1);
      backend.value = PlaybackSnapshot(
        connected: true,
        isPlaying: true,
        isReady: true,
        playWhenReady: true,
        position: const Duration(seconds: 47),
        duration: const Duration(minutes: 3),
        mediaId: 'current',
        title: 'current',
        artist: 'Artist',
        album: 'Album',
        currentQueueIndex: 1,
        queueLength: 3,
        volume: 1,
        hasError: false,
        error: null,
      );
      backend.controller.add(backend.value);
      await Future<void>.delayed(Duration.zero);
      backend.commandOrder.clear();
      backend.playing = true;

      await runtime.synchronizeQueue([first, current, makeSong('added'), last]);

      expect(runtime.queue.map((song) => song.id), ['first', 'current', 'added', 'last']);
      expect(backend.loadedIndex, 1);
      expect(backend.loaded[backend.loadedIndex].id, 'current');
      expect(backend.lastSeek, const Duration(seconds: 47));
      expect(backend.playing, isTrue);
      expect(backend.cancelCrossfadeCalls, 1);
      expect(backend.commandOrder, ['seek', 'play']);
    });

    test('synchronizes queue when current track was removed using nearest playable item', () async {
      final current = makeSong('current');
      final next = makeSong('next');
      await runtime.loadQueue([current, next], startIndex: 0);
      backend.value = PlaybackSnapshot(
        connected: true,
        isPlaying: false,
        isReady: true,
        playWhenReady: false,
        position: const Duration(seconds: 31),
        duration: const Duration(minutes: 3),
        mediaId: 'current',
        title: 'current',
        artist: 'Artist',
        album: 'Album',
        currentQueueIndex: 0,
        queueLength: 2,
        volume: 1,
        hasError: false,
        error: null,
      );
      backend.controller.add(backend.value);
      await Future<void>.delayed(Duration.zero);
      backend.commandOrder.clear();

      await runtime.synchronizeQueue([next, makeSong('new')]);

      expect(backend.loadedIndex, 0);
      expect(backend.loaded[0].id, 'next');
      // The old track's timestamp belongs to the removed item and must
      // not jump the replacement track forward by 31 seconds.
      expect(backend.lastSeek, isNull);
      expect(backend.playing, isFalse);
      expect(backend.commandOrder, ['pause-start', 'pause-end']);
    });

    test('command lane remains usable after queue synchronization fails', () async {
      final stable = makeSong('stable');
      await runtime.loadQueue([stable]);
      backend.recordLoadCommands = true;
      backend.failLoad = true;

      await expectLater(
        runtime.synchronizeQueue([makeSong('rejected')]),
        throwsA(isA<StateError>()),
      );
      await runtime.play();

      expect(runtime.queue.map((song) => song.id), ['stable']);
      expect(backend.loaded.map((song) => song.id), ['stable']);
      expect(backend.commandOrder, ['loadQueue-start', 'play']);
      expect(backend.playing, isTrue);
    });

    test('queue synchronization waits behind an in-flight transport command', () async {
      final current = makeSong('current');
      final replacement = makeSong('replacement');
      await runtime.loadQueue([current], startIndex: 0);
      backend.pauseGate = Completer<void>();
      backend.recordLoadCommands = true;

      final pause = runtime.pause();
      final synchronize = runtime.synchronizeQueue([replacement]);
      await Future<void>.delayed(Duration.zero);

      // Queue replacement must not overtake a transport command already in
      // the serialized lane.
      expect(backend.loaded.map((song) => song.id), ['current']);
      expect(backend.commandOrder, ['pause-start']);

      backend.pauseGate!.complete();
      await Future.wait([pause, synchronize]);

      expect(backend.loaded.map((song) => song.id), ['replacement']);
      expect(backend.commandOrder, [
        'pause-start',
        'pause-end',
        'loadQueue-start',
        'loadQueue-end',
        'pause-start',
        'pause-end',
      ]);
    });

    test('queue synchronization filters unplayable entries before resolving index', () async {
      final first = makeSong('first');
      final current = makeSong('current');
      await runtime.loadQueue([first, current], startIndex: 1);
      // Keep the fake backend's command state consistent with the snapshot
      // emitted below; unchanged synchronization must preserve active playback.
      backend.playing = true;
      backend.value = PlaybackSnapshot(
        connected: true,
        isPlaying: true,
        isReady: true,
        playWhenReady: true,
        position: const Duration(seconds: 22),
        duration: const Duration(minutes: 3),
        mediaId: 'current',
        title: 'current',
        artist: 'Artist',
        album: 'Album',
        currentQueueIndex: 1,
        queueLength: 2,
        volume: 1,
        hasError: false,
        error: null,
      );
      backend.controller.add(backend.value);
      await Future<void>.delayed(Duration.zero);
      backend.commandOrder.clear();

      await runtime.synchronizeQueue([
        makeSong('unplayable', path: ' '),
        first,
        makeSong('also-unplayable', path: ''),
        current,
      ]);

      expect(runtime.queue.map((song) => song.id), ['first', 'current']);
      expect(backend.loaded.map((song) => song.id), ['first', 'current']);
      expect(backend.loadedIndex, 1);
      expect(backend.loaded[backend.loadedIndex].id, 'current');
      // Filtering the unplayable entries leaves the native queue unchanged,
      // so synchronization must not reload or seek the active item.
      expect(backend.lastSeek, isNull);
      expect(backend.playing, isTrue);
    });

    test('forwards transport commands to the backend', () async {
      await runtime.play();
      expect(backend.playing, isTrue);
      await runtime.pause();
      expect(backend.playing, isFalse);
    });
  });
}
