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
  int _snapshotRevision = 0;
  bool _queueLoadInProgress = false;
  PlaybackSnapshot? _pendingQueueSnapshot;
  Future<void> _connectTail = Future<void>.value();
  Future<void> _commandTail = Future<void>.value();

  Stream<Media3RuntimeState> get states => _states.stream;
  Media3RuntimeState get current => _current;
  List<Song> get queue => List<Song>.unmodifiable(_queue);

  /// Starts listening before reading the initial state so a fast native state
  /// update cannot be missed between the snapshot request and subscription.
  Future<void> connect() {
    _ensureAlive();
    // Session startup can be requested by multiple owners at once. Serialize
    // reconnects so two callers cannot both pass the cancellation await and
    // leave duplicate native-state subscriptions behind.
    final result = _connectTail.then((_) {
      _ensureAlive();
      return _connectOnce();
    });
    _connectTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> _connectOnce() async {
    await _subscription?.cancel();
    _ensureAlive();
    _subscription = _backend.states.listen((snapshot) {
      if (_disposed) return;
      _snapshotRevision++;
      if (_queueLoadInProgress) {
        // Do not publish a native event against the old queue while a new
        // queue is being installed. The latest event is reconciled once the
        // backend has either accepted or rejected the replacement.
        _pendingQueueSnapshot = snapshot;
        return;
      }
      _acceptSnapshot(snapshot);
    });
    final revisionBeforeRead = _snapshotRevision;
    try {
      final initial = await _backend.currentState();
      // Disposal may happen while the native snapshot request is in flight.
      // Never publish late state after the runtime has closed its stream.
      if (_disposed) return;
      // A stream event received while the snapshot request was in flight is
      // newer than that request's result. Never let the delayed read roll state
      // backwards after reconnecting to the native service.
      if (_snapshotRevision == revisionBeforeRead) {
        _acceptSnapshot(initial);
      }
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
      // Buffer native snapshots while queue identity is changing. Publishing
      // them immediately would reconcile a new native index against the old
      // Dart queue and briefly expose the wrong current song.
      _queueLoadInProgress = true;
      _pendingQueueSnapshot = null;
      try {
        await _backend.loadQueue(nextQueue, startIndex: startIndex);
        // Disposal can race a slow native queue load. Do not commit queue
        // identity or publish post-disposal state when that load eventually
        // completes.
        _ensureAlive();
      } catch (_) {
        _queueLoadInProgress = false;
        final pending = _pendingQueueSnapshot;
        _pendingQueueSnapshot = null;
        if (pending != null) {
          // A failed replacement never commits its queue identity. Reconcile a
          // buffered native event only if it can still identify an item in the
          // previously committed queue; otherwise it may describe a partial
          // native replacement and must not erase the last known-good state.
          final pendingIndex =
              Media3MusicProviderAdapter.resolveCurrentQueueIndex(
            _queue,
            mediaId: pending.mediaId,
            playableIndex: pending.currentQueueIndex,
          );
          if (pendingIndex != null) _acceptSnapshot(pending);
        }
        rethrow;
      }

      // Commit queue identity only after the backend accepted the queue.
      _queue = nextQueue;
      _queueLoadInProgress = false;
      final pending = _pendingQueueSnapshot;
      _pendingQueueSnapshot = null;
      if (pending != null) {
        final pendingIndex =
            Media3MusicProviderAdapter.resolveCurrentQueueIndex(
          _queue,
          mediaId: pending.mediaId,
          playableIndex: pending.currentQueueIndex,
        );
        // Drop an outgoing-queue snapshot rather than briefly clearing or
        // misidentifying the newly selected track. A fresh state read below
        // or the next native event will publish the accepted queue's state.
        if (pendingIndex != null) _acceptSnapshot(pending);
      }

      final revisionBeforeRead = _snapshotRevision;
      try {
        final loadedState = await _backend.currentState();
        if (_snapshotRevision == revisionBeforeRead) {
          _acceptSnapshot(loadedState);
        }
      } catch (_) {
        // The native event stream remains authoritative if a snapshot read is
        // temporarily unavailable after a successful queue load.
      }
    });
  }

  /// Clears queue identity only after the native backend accepts the clear.
  /// A failed command preserves the last committed Dart queue and state.
  Future<void> clearQueue() async {
    _ensureAlive();
    await _run(() async {
      _queueLoadInProgress = true;
      _pendingQueueSnapshot = null;
      try {
        await _backend.clearQueue();
        _ensureAlive();
      } catch (_) {
        _queueLoadInProgress = false;
        final pending = _pendingQueueSnapshot;
        _pendingQueueSnapshot = null;
        if (pending != null) {
          // A rejected clear must retain the previously committed queue. Ignore
          // snapshots that can only describe a partially-cleared native queue.
          final pendingIndex =
              Media3MusicProviderAdapter.resolveCurrentQueueIndex(
            _queue,
            mediaId: pending.mediaId,
            playableIndex: pending.currentQueueIndex,
          );
          if (pendingIndex != null) _acceptSnapshot(pending);
        }
        rethrow;
      }
      _queue = const <Song>[];
      _queueLoadInProgress = false;
      _pendingQueueSnapshot = null;
      final revisionBeforeRead = _snapshotRevision;
      try {
        final clearedState = await _backend.currentState();
        // A native state event delivered while the follow-up read was in
        // flight is newer than that read. Do not let a delayed snapshot roll
        // the reconciled state backwards after the queue has been cleared.
        if (_snapshotRevision == revisionBeforeRead) {
          _acceptSnapshot(clearedState);
        }
      } catch (_) {
        // Native clear was accepted, so never leave a stale current song
        // visible just because the follow-up snapshot was temporarily lost.
        // But don't erase a newer state event that arrived during the read.
        if (_snapshotRevision == revisionBeforeRead) {
          _current = const Media3RuntimeState.empty();
          if (!_states.isClosed) _states.add(_current);
        }
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

    await _run(() async {
      // Resolve against the queue that actually precedes this command in the
      // serialized lane, not a stale queue captured before a pending load.
      final resolvedIndex = queueIndex ?? _resolveIncomingQueueIndex(song);
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
