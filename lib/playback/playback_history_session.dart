import 'dart:async';

import '../models/listening_event.dart';

/// Owns the mutable state and serialization chain for one active listening
/// session. Persistence and playback policy remain with MusicProvider.
class PlaybackHistorySession {
  ListeningEvent? activeEvent;
  int positionMs = 0;
  Future<void> _serial = Future<void>.value();
  bool _operationActive = false;

  bool get operationActive => _operationActive;

  /// Runs history mutations in order, even when an earlier operation fails.
  Future<void> enqueue(Future<void> Function() operation) {
    final next = _serial.then((_) async {
      _operationActive = true;
      try {
        await operation();
      } finally {
        _operationActive = false;
      }
    });
    _serial = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  void updatePosition(int value) {
    positionMs = value;
  }

  void clear() {
    activeEvent = null;
    positionMs = 0;
  }
}
