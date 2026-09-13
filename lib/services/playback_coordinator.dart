import 'dart:async';

/// Owns the ordering boundary for native playback mutations.
///
/// Source-changing operations are strictly serialized because just_audio can
/// reject overlapping setAudioSource/stop operations. Transport commands are
/// intentionally not placed behind that queue: pause, seek and stop should
/// remain responsive while a source operation is resolving.
class PlaybackCoordinator {
  Future<void> _sourceTail = Future<void>.value();
  int _operationId = 0;

  int get lastOperationId => _operationId;

  Future<T> runSourceMutation<T>(
    Future<T> Function() operation, {
    required String command,
  }) {
    final id = ++_operationId;
    final next = _sourceTail.then((_) async {
      try {
        return await operation();
      } catch (_) {
        rethrow;
      }
    });
    _sourceTail = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  /// Transport operations intentionally bypass the source-mutation queue.
  /// They still run through one explicit boundary so callers have a single
  /// place to enforce future transport policy without touching the player.
  Future<T> runTransport<T>(Future<T> Function() operation) => operation();

  /// Wait until every queued source mutation has settled.
  Future<void> drain() => _sourceTail;

  void reset() {
    // A completed tail is enough to release retained futures without touching
    // an in-flight native operation.
    _sourceTail = Future<void>.value();
  }
}
