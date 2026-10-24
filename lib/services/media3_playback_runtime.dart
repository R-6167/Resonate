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

    _queue = List<Song>.unmodifiable(songs);
    await _backend.loadQueue(_queue, startIndex: startIndex);
    // Do not optimistically claim a song is playing. The backend state stream
    // remains authoritative for current item and transport state.
  }

  Future<void> play() => _run(_backend.play);
  Future<void> pause() => _run(_backend.pause);
  Future<void> stop() => _run(_backend.stop);
  Future<void> seek(Duration position) => _run(() => _backend.seek(position));
  Future<void> next() => _run(_backend.next);
  Future<void> previous() => _run(_backend.previous);
  Future<void> setVolume(double value) => _run(() => _backend.setVolume(value));
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode) =>
      _run(() => _backend.setRepeatMode(mode));

  Future<void> _run(Future<void> Function() command) async {
    _ensureAlive();
    await command();
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
