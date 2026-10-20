/// Deterministic timing policy for automatic crossfade and preload decisions.
///
/// This class deliberately does not own audio players or execute handoffs;
/// MusicProvider remains responsible for validating ownership and performing
/// the transition. Keeping timing calculations pure makes them testable without
/// invoking native audio engines.
class CrossfadeOrchestrator {
  const CrossfadeOrchestrator._();

  static CrossfadeTiming timing({
    required int configuredDurationMs,
    required bool djActive,
  }) {
    final effectiveFadeMs = djActive
        ? configuredDurationMs.clamp(500, 6500).toInt()
        : configuredDurationMs;
    final startMarginMs = (1200 + (effectiveFadeMs ~/ 10))
        .clamp(1500, 3000)
        .toInt();

    return CrossfadeTiming(
      effectiveFadeMs: effectiveFadeMs,
      preloadWindowMs: (configuredDurationMs + 10000).clamp(10000, 28000).toInt(),
      fadeArmWindowMs: configuredDurationMs + 2000,
      triggerWindowMs: (effectiveFadeMs + startMarginMs).clamp(2000, 16000).toInt(),
    );
  }
}

class CrossfadeTiming {
  const CrossfadeTiming({
    required this.effectiveFadeMs,
    required this.preloadWindowMs,
    required this.fadeArmWindowMs,
    required this.triggerWindowMs,
  });

  final int effectiveFadeMs;
  final int preloadWindowMs;
  final int fadeArmWindowMs;
  final int triggerWindowMs;
}
