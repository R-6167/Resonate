import 'dart:async';

import '../models/song.dart';
import 'media3_playback_runtime.dart';

/// Projects the serialized Media3 runtime into the small state surface that
/// MusicProvider and its UI consumers need.
///
/// This is intentionally a state-only bridge: it never creates a player, issues
/// commands, or optimistically changes playback state. The production provider
/// can subscribe to this projection while transport ownership is migrated in
/// separate, testable steps.
class Media3ProviderStateBridge {
  Media3ProviderStateBridge(this._runtime);

  final Media3PlaybackRuntime _runtime;
  final StreamController<Media3ProviderState> _states =
      StreamController<Media3ProviderState>.broadcast();

  StreamSubscription<Media3RuntimeState>? _subscription;
  Media3ProviderState _current = const Media3ProviderState.empty();
  bool _started = false;
  bool _disposed = false;

  Stream<Media3ProviderState> get states => _states.stream;
  Media3ProviderState get current => _current;

  /// Subscribes before publishing the runtime's current value, avoiding a gap
  /// where a state update could be lost during provider attachment.
  Future<void> start() async {
    if (_disposed) throw StateError('Media3ProviderStateBridge is disposed.');
    if (_started) return;
    _started = true;
    _subscription = _runtime.states.listen(_accept);
    _accept(_runtime.current);
  }

  void _accept(Media3RuntimeState state) {
    if (_disposed) return;
    final snapshot = state.snapshot;
    _current = Media3ProviderState(
      currentSong: state.currentSong,
      queueIndex: state.currentQueueIndex,
      isPlaying: state.isPlaying,
      position: state.position,
      duration: state.duration,
      connected: state.connected,
      isReady: snapshot?.isReady ?? false,
      playWhenReady: snapshot?.playWhenReady ?? false,
      mediaId: snapshot?.mediaId,
      queueLength: snapshot?.queueLength ?? 0,
      volume: snapshot?.volume ?? 1.0,
      repeatMode: snapshot?.repeatMode ?? 'off',
      shuffleModeEnabled: snapshot?.shuffleModeEnabled ?? false,
      hasError: state.hasError,
      error: state.error,
    );
    // The empty runtime state is useful as the initial value but should not
    // masquerade as a native update to consumers until a snapshot exists.
    if (snapshot != null && !_states.isClosed) _states.add(_current);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _states.close();
  }
}

/// Immutable provider-facing state; playback truth always comes from Media3.
class Media3ProviderState {
  const Media3ProviderState({
    required this.currentSong,
    required this.queueIndex,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.connected,
    required this.isReady,
    required this.playWhenReady,
    required this.mediaId,
    required this.queueLength,
    required this.volume,
    this.repeatMode = 'off',
    this.shuffleModeEnabled = false,
    required this.hasError,
    required this.error,
  });

  const Media3ProviderState.empty()
      : currentSong = null,
        queueIndex = null,
        isPlaying = false,
        position = Duration.zero,
        duration = null,
        connected = false,
        isReady = false,
        playWhenReady = false,
        mediaId = null,
        queueLength = 0,
        volume = 1.0,
        repeatMode = 'off',
        shuffleModeEnabled = false,
        hasError = false,
        error = null;

  final Song? currentSong;
  final int? queueIndex;
  final bool isPlaying;
  final Duration position;
  final Duration? duration;
  final bool connected;
  final bool isReady;
  final bool playWhenReady;
  final String? mediaId;
  final int queueLength;
  final double volume;
  final String repeatMode;
  final bool shuffleModeEnabled;
  final bool hasError;
  final String? error;
}
