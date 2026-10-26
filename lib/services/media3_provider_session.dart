import 'dart:async';

import '../models/song.dart';
import 'media3_music_provider_adapter.dart';
import 'media3_playback_runtime.dart';
import 'media3_provider_state_bridge.dart';
import 'playback_backend.dart';
import 'playback_observation_source.dart';

/// Composition root for the Media3 provider migration.
///
/// It owns one serialized runtime and one provider-facing state projection.
/// MusicProvider can adopt this session behind its existing compatibility
/// boundary without constructing multiple clients or listening to native
/// snapshots independently. It is not wired into production MusicProvider yet.
class Media3ProviderSession implements PlaybackObservationSource {
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

  List<Song> get queue => _runtime.queue;

  /// Connects the backend before publishing its initial reconciled state.
  /// Safe to call repeatedly; the runtime and bridge both make startup
  /// idempotent.
  Future<void> start() async {
    _ensureAlive();
    if (_started) return;
    await _runtime.connect();
    await _bridge.start();
    _started = true;
  }

  Future<void> loadQueue(List<Song> songs, {int startIndex = 0}) =>
      _runtime.loadQueue(songs, startIndex: startIndex);
  Future<void> play() => _runtime.play();
  Future<void> pause() => _runtime.pause();
  Future<void> stop() => _runtime.stop();
  Future<void> seek(Duration position) => _runtime.seek(position);
  Future<void> next() => _runtime.next();
  Future<void> previous() => _runtime.previous();
  Future<void> setVolume(double value) => _runtime.setVolume(value);
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode) =>
      _runtime.setRepeatMode(mode);
  Future<void> setShuffleMode(bool enabled) =>
      _runtime.setShuffleMode(enabled);
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

  Future<void> preloadNext(Song song, {int? queueIndex}) =>
      _runtime.preloadNext(song, queueIndex: queueIndex);
  Future<void> crossfade({required Duration duration}) =>
      _runtime.crossfade(duration: duration);
  Future<void> cancelCrossfade() => _runtime.cancelCrossfade();

  void _ensureAlive() {
    if (_disposed) throw StateError('Media3ProviderSession is disposed.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _bridge.dispose();
    await _runtime.dispose();
  }
}
