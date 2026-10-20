/// Normalized elapsed progress for one crossfade frame.
///
/// This is intentionally pure: it does not control timing, player state, or
/// transition ownership. Values are bounded so monitoring and DJ effects see
/// a stable fraction even if a frame runs before/after the planned window.
class CrossfadeFrameProgress {
  const CrossfadeFrameProgress(this.fraction);

  final double fraction;

  static CrossfadeFrameProgress calculate({
    required int elapsedMs,
    required int totalMs,
  }) {
    if (totalMs <= 0) return const CrossfadeFrameProgress(1.0);
    return CrossfadeFrameProgress(
      (elapsedMs / totalMs).clamp(0.0, 1.0),
    );
  }
}
