import 'dart:math' as math;

/// Pure gain policy for the short outgoing-only ramp used by crossfade fallback.
/// This does not schedule frames or control the player.
class CrossfadeFallbackFade {
  const CrossfadeFallbackFade._();

  /// Equal-power cosine ramp: 1 at the start, 0 at the end.
  /// Out-of-range progress is clamped to keep gain finite and bounded.
  static double outgoingGain(double progress) {
    final t = progress.clamp(0.0, 1.0).toDouble();
    return math.cos(t * (math.pi / 2.0)).clamp(0.0, 1.0).toDouble();
  }
}
