import 'dart:async';

import '../models/song.dart';
import 'media3_music_provider_adapter.dart';
import 'media3_playback_runtime.dart';
import 'media3_provider_state_bridge.dart';
import 'playback_backend.dart';
import 'playback_engine_session.dart';

/// Composition root for the Media3 provider migration.
///
/// It owns one serialized runtime and one provider-facing state projection.
/// MusicProvider can adopt this session behind its existing compatibility
/// boundary without constructing multiple clients or listening to native
/// snapshots independently. It is not wired into production MusicProvider yet.
class Media3ProviderSession implements PlaybackEngineSession {
  Media3ProviderSession({PlaybackBackend? backend})
      : _runtime = Media3PlaybackRuntime(
          backend ?? Media3MusicProviderAdapter(),
        ) {
    _bridge = Media3ProviderStateBridge(_runtime);
  }

  final Media3PlaybackRuntime _runtime;
  late final Media3ProviderStateBridge _bridge;
  bool _started = false;
  bool _disposed = false;
  Future<void>? _startFuture;

  Stream<Media3ProviderState> get states => _bridge.states;
  Media3ProviderState get current => _bridge.current;

  /// Compatibility observations for UI consumers that previously subscribed
  /// directly to just_audio's active-player streams. Values are projected from
  /// reconciled Media3 snapshots; they never issue playback commands.
  @override
  Stream<Duration> get positionStream =>
      states.map((state) => state.position);
  @override
  Stream<Duration?> get durationStream =>
      states.map((state) => state.duration);
  @override
  Stream<bool> get playingStream =>
      states.map((state) => state.isPlaying);

  @override
  List<Song> get queue => _runtime.queue;

  /// Connects the backend before publishing its initial reconciled state.
  /// Safe to call repeatedly; the runtime and bridge both make startup
  /// idempotent.
  @override
  Future<void> start() {
    // Preserve the Future-based contract: callers observe disposed startup
    // as an asynchronous StateError rather than a synchronous throw.
    if (_disposed) {
      return Future<void>.error(
        StateError('Media3ProviderSession is disposed.'),
      );
    }
    if (_started) return Future<void>.value();
    final pending = _startFuture;
    if (pending != null) return pending;

    // Publish the in-flight future before yielding. Concurrent owners must
    // share one connection attempt instead of serially reconnecting the
    // backend and racing bridge initialization.
    final starting = _startOnce();
    _startFuture = starting;
    return starting;
  }

  Future<void> _startOnce() async {
    try {
      await _runtime.connect();
      _ensureAlive();
      await _bridge.start();
      _ensureAlive();
      _started = true;
    } catch (_) {
      // A failed connection must not permanently poison retries.
      _startFuture = null;
      rethrow;
    }
  }

  @override
  Future<void> loadQueue(List<Song> songs, {int startIndex = 0}) =>
      _runtime.loadQueue(songs, startIndex: startIndex);
  @override
  Future<void> play() => _runtime.play();
  @override
  Future<void> pause() => _runtime.pause();
  @override
  Future<void> stop() => _runtime.stop();
  @override
  Future<void> seek(Duration position) => _runtime.seek(position);
  @override
  Future<void> next() => _runtime.next();
  @override
  Future<void> previous() => _runtime.previous();
  @override
  Future<void> setVolume(double value) => _runtime.setVolume(value);
  @override
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode) =>
      _runtime.setRepeatMode(mode);
  @override
  Future<void> setShuffleMode(bool enabled) =>
      _runtime.setShuffleMode(enabled);
  @override
  Future<void> setGainFactors({
    double? trackLevel,
    double? preamp,
    double? sleepFade,
    double? focusDuck,
  }) =>
      _runtime.setGainFactors(
        trackLevel: trackLevel,
        preamp: preamp,
        sleepFade: sleepFade,
        focusDuck: focusDuck,
      );

  @override
  Future<void> preloadNext(Song song, {int? queueIndex}) =>
      _runtime.preloadNext(song, queueIndex: queueIndex);
  @override
  Future<void> crossfade({required Duration duration}) =>
      _runtime.crossfade(duration: duration);
  @override
  Future<void> cancelCrossfade() => _runtime.cancelCrossfade();

  void _ensureAlive() {
    if (_disposed) throw StateError('Media3ProviderSession is disposed.');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // A failed observer shutdown must not leave the native Media3 runtime
    // connected in the background. The session owns both resources.
    try {
      await _bridge.dispose();
    } finally {
      await _runtime.dispose();
    }
  }
}
