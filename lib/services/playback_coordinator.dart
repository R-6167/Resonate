import 'dart:async';

/// Serializes native source mutations while allowing newer user source
/// requests to supersede requests that have not started yet.
class PlaybackCoordinator {
  Future<void> _sourceTail = Future<void>.value();
  int _operationId = 0;
  int _latestSourceRequest = 0;

  int get lastOperationId => _operationId;

  Future<T> runSourceMutation<T>(
    Future<T> Function() operation, {
    required String command,
    bool supersedePending = false,
    Future<T> Function()? onSuperseded,
  }) {
    final id = ++_operationId;
    if (supersedePending) _latestSourceRequest = id;
    final next = _sourceTail.then((_) async {
      if (supersedePending && id != _latestSourceRequest) {
        if (onSuperseded != null) return onSuperseded();
        return operation();
      }
      return operation();
    });
    _sourceTail = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<T> runTransport<T>(Future<T> Function() operation) => operation();

  Future<void> drain() => _sourceTail;

  void reset() {
    _sourceTail = Future<void>.value();
    _latestSourceRequest = _operationId;
  }
}
