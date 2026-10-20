/// User-transport authority tokens and in-flight gates.
///
/// Owns the monotonic epoch that invalidates automatic crossfade work, plus
/// flags that mark "user is driving transport / source load". Crossfade
/// generations stay on [CrossfadeRuntime]; this type is the complementary
/// half of "transport always wins".
class TransportEpoch {
  /// Bumped on every user transport (play/next/prev/pause). Automatic
  /// crossfade captures this and aborts if it changes mid-flight.
  int epoch = 0;

  bool inFlight = false;
  int pendingCount = 0;
  bool userWantsPlaying = false;
  bool loadingSource = false;

  bool get isPending => pendingCount > 0;

  /// Transport or source load is busy — automatic work should usually wait.
  bool get isBusy => inFlight || loadingSource || isPending;

  int bump() => ++epoch;

  bool owns(int captured) => epoch == captured;

  void beginPending() {
    pendingCount++;
  }

  void endPending() {
    if (pendingCount > 0) pendingCount--;
  }
}
