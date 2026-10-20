/// Pure queue-target policy used when an automatic crossfade must fall back
/// to ordinary playback. It does not mutate queue state or start playback.
class CrossfadeFallbackTarget {
  const CrossfadeFallbackTarget._();

  /// Returns the next queue index, wraps only for repeat-all, or -1 if none.
  static int nextIndex({
    required int currentIndex,
    required int queueLength,
    required bool repeatAll,
  }) {
    if (queueLength <= 0 || currentIndex < 0 || currentIndex >= queueLength) {
      return -1;
    }
    if (currentIndex < queueLength - 1) return currentIndex + 1;
    return repeatAll ? 0 : -1;
  }
}
