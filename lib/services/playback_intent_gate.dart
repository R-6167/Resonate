/// Monotonically increasing token used to invalidate stale playback work.
///
/// The gate is deliberately independent of audio plugins so its concurrency
/// semantics can be covered by fast unit tests.
class PlaybackIntentGate {
  int _token = 0;

  int get currentToken => _token;

  int issue() => ++_token;

  bool isCurrent(int token) => token == _token;
}
