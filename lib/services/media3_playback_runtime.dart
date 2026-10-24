import 'dart:async';

import '../models/song.dart';
import 'media3_music_provider_adapter.dart';
import 'playback_backend.dart';
import 'playback_snapshot.dart';

/// Provider-facing Media3 runtime: one backend, one queue, one reconciled state.
///
/// This is deliberately isolated from MusicProvider while the remaining DSP,
/// focus, and crossfade responsibilities are migrated. It is not enabled in
/// production until that cutover is complete.
class Media3PlaybackRuntime {
  Media3PlaybackRuntime(this._backend);

  final PlaybackBackend _backend;
  final StreamController<Media3RuntimeState> _states =
      StreamController<Media3RuntimeState>.broadcast();

  StreamSubscription<PlaybackSnapshot>? _subscription;
  List<Song> _queue = const <Song>[];
  Media3RuntimeState _current = const Media3RuntimeState.empty();
  bool _disposed = false;
  Future<void> _commandTail = Future<void>.value();

  Stream<Media3RuntimeState> get states => _states.stream;
  Media3RuntimeState get current => _current;
  List<Song> get queue => List<Song>.unmodifiable(_queue);

  /// Starts listening before reading the initial state so a fast native state
  /// update cannot be missed between the snapshot request and subscription.
  Future<void> connect() async {
    if (_disposed) throw StateError('Media3PlaybackRuntime is disposed.');
    await _subscription?.cancel();
    _subscription = _backend.states.listen(_acceptSnapshot);
    try {
      _acceptSnapshot(await _backend.currentState());
    } catch (_) {
      // A not-yet-connected native service will publish its first valid state
      // through the stream. Keep the runtime alive for that connection.
    }
  }

  Future<void> loadQueue(List<Song> songs, {int startIndex = 0}) async {
    _ensureAlive();
    if (songs.isEmpty) throw ArgumentError.value(songs, 'songs', 'Queue must not be empty.');
    if (startIndex < 0 || startIndex >= songs.length) {
      throw ArgumentError.value(startIndex, 'startIndex', 'Must identify an item in the queue.');
    }
    if (songs[startIndex].filePath.trim().isEmpty) {
      throw ArgumentError.value(startIndex, 'startIndex', 'Selected track is not playable.');
    }
    if (!songs.any((song) => song.filePath.trim().isNotEmpty)) {
      throw ArgumentError.value(songs, 'songs', 'Queue contains no playable tracks.');
    }

    final nextQueue = List<Song>.unmodifiable(songs);
    await _run(() async {
      // Commit queue identity only after the backend accepted the queue. This
      // prevents failed loads from leaving snapshots mapped to a queue that
      // the engine never actually installed.
      await _backend.loadQueue(nextQueue, startIndex: startIndex);
      _queue = nextQueue;
      try {
        _acceptSnapshot(await _backend.currentState());
      } catch (_) {
        // The native event stream remains authoritative if a snapshot read is
        // temporarily unavailable after a successful queue load.
      }
    });
  }

  Future<void> play() => _run(_backend.play);
  Future<void> pause() => _run(_backend.pause);
  Future<void> stop() => _run(_backend.stop);
  Future<void> seek(Duration position) => _run(() => _backend.seek(position));
  Future<void> next() => _run(_backend.next);
  Future<void> previous() => _run(_backend.previous);
  Future<void> setVolume(double value) => _run(() => _backend.setVolume(value));
  Future<void> setGainFactors({
    double? trackLevel,
    double? preamp,
    double? sleepFade,
    double? focusDuck,
  }) => _run(() => _backend.setGainFactors(
        trackLevel: trackLevel,
        preamp: preamp,
        sleepFade: sleepFade,
        focusDuck: focusDuck,
      ));
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode) =>
      _run(() => _backend.setRepeatMode(mode));
  Future<void> setShuffleMode(bool enabled) =>
      _run(() => _backend.setShuffleMode(enabled));

  /// Prepares the incoming song on the Media3 standby deck without disturbing
  /// the current deck. Only a backend with native dual-deck support may do this.
  Future<void> preloadNext(Song song, {int? queueIndex}) async {
    _ensureAlive();
    if (_backend is! PlaybackCrossfadeBackend) {
      throw UnsupportedError('This playback backend does not support native crossfade.');
    }

    final resolvedIndex = queueIndex ?? _resolveIncomingQueueIndex(song);
    await _run(() async {
      if (_queue.isNotEmpty && resolvedIndex != null) {
        await (_backend as PlaybackCrossfadeBackend).preloadNext(
          song,
          queue: _queue,
          startIndex: resolvedIndex,
        );
        return;
      }
      await (_backend as PlaybackCrossfadeBackend).preloadNext(song);
    });
  }

  int? _resolveIncomingQueueIndex(Song song) {
    if (_queue.isEmpty) return null;
    final currentIndex = _current.currentQueueIndex ?? -1;
    // Prefer the next matching occurrence after the current item. This preserves
    // queue occurrence identity when a playlist contains the same song twice.
    for (var i = currentIndex + 1; i < _queue.length; i++) {
      if (_sameTrack(_queue[i], song)) return i;
    }
    int? uniqueMatch;
    for (var i = 0; i < _queue.length; i++) {
      if (!_sameTrack(_queue[i], song)) continue;
      if (uniqueMatch != null) return null;
      uniqueMatch = i;
    }
    return uniqueMatch;
  }

  bool _sameTrack(Song left, Song right) =>
      left.id == right.id && left.filePath.trim() == right.filePath.trim();

  Future<void> crossfade({required Duration duration}) async {
    _ensureAlive();
    if (duration < const Duration(milliseconds: 250) ||
        duration > const Duration(seconds: 15)) {
      throw ArgumentError.value(duration, 'duration', 'Must be between 250 ms and 15 s.');
    }
    if (_backend is! PlaybackCrossfadeBackend) {
      throw UnsupportedError('This playback backend does not support native crossfade.');
    }
    await _run(() => (_backend as PlaybackCrossfadeBackend).crossfade(duration: duration));
  }

  Future<void> cancelCrossfade() async {
    _ensureAlive();
    if (_backend is! PlaybackCrossfadeBackend) {
      throw UnsupportedError('This playback backend does not support native crossfade.');
    }
    await _run(() => (_backend as PlaybackCrossfadeBackend).cancelCrossfade());
  }

  /// Serializes every command that can mutate native playback state. Rapid
  /// UI taps, queue replacement and a crossfade request must not race each
  /// other across the Flutter/native boundary.
  Future<void> _run(Future<void> Function() command) {
    _ensureAlive();
    final result = _commandTail.then((_) {
      _ensureAlive();
      return command();
    });
    // Keep the lane usable after one failed command while still returning that
    // failure to the caller that issued it.
    _commandTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void _acceptSnapshot(PlaybackSnapshot snapshot) {
    if (_disposed) return;
    final index = Media3MusicProviderAdapter.resolveCurrentQueueIndex(
      _queue,
      mediaId: snapshot.mediaId,
      playableIndex: snapshot.currentQueueIndex,
    );
    final song = index == null ? null : _queue[index];
    _current = Media3RuntimeState(
      snapshot: snapshot,
      currentSong: song,
      currentQueueIndex: index,
    );
    if (!_states.isClosed) _states.add(_current);
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('Media3PlaybackRuntime is disposed.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _states.close();
  }
}

class Media3RuntimeState {
  const Media3RuntimeState({
    required this.snapshot,
    required this.currentSong,
    required this.currentQueueIndex,
  });

  const Media3RuntimeState.empty()
      : snapshot = null,
        currentSong = null,
        currentQueueIndex = null;

  final PlaybackSnapshot? snapshot;
  final Song? currentSong;
  final int? currentQueueIndex;

  bool get isPlaying => snapshot?.isPlaying ?? false;
  Duration get position => snapshot?.position ?? Duration.zero;
  Duration? get duration => snapshot?.duration;
  bool get connected => snapshot?.connected ?? false;
  bool get hasError => snapshot?.hasError ?? false;
  String? get error => snapshot?.error;
}
