import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Owns the lifecycle of the active player's state, position, and duration
/// subscriptions. MusicProvider continues to own playback decisions and side effects.
class PlayerStreamBinder {
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  void bindPlayerState(
    Stream<PlayerState> stream,
    void Function(PlayerState state) onData,
  ) {
    unawaited(_playerStateSubscription?.cancel());
    _playerStateSubscription = stream.listen(onData);
  }

  void bindPosition(
    Stream<Duration> stream,
    void Function(Duration position) onData,
  ) {
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = stream.listen(onData);
  }

  void bindDuration(
    Stream<Duration?> stream,
    void Function(Duration? duration) onData,
  ) {
    unawaited(_durationSubscription?.cancel());
    _durationSubscription = stream.listen(onData);
  }

  void cancel() {
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    _playerStateSubscription = null;
    _positionSubscription = null;
    _durationSubscription = null;
  }
}
