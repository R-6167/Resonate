import 'dart:math' as math;

/// Deterministic timing policy and fade-curve math for crossfade execution.
///
/// This class deliberately does not own audio players or execute handoffs;
/// MusicProvider remains responsible for validating ownership and performing
/// the transition. Keeping timing calculations pure makes them testable without
/// invoking native audio engines.
class CrossfadeOrchestrator {
  const CrossfadeOrchestrator._();

  /// Computes the existing eased, equal-power A/B gains for one fade frame.
  /// Keeps the curve deterministic and independent of native audio players.
  static CrossfadeGains gains({
    required int elapsedMs,
    required int totalMs,
    required String fadeType,
  }) {
    final linear = (elapsedMs / totalMs).clamp(0.0, 1.0);
    final eased = switch (fadeType) {
      'ease_in' => linear * linear,
      'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)),
      'ease_in_out' => linear < 0.5
          ? 2.0 * linear * linear
          : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0,
      _ => linear,
    };
    final outT = math.pow(eased, 1.28).toDouble().clamp(0.0, 1.0);
    final inT = math.pow(eased, 0.92).toDouble().clamp(0.0, 1.0);
    return CrossfadeGains(
      outgoing: math.cos(outT * (math.pi / 2.0)),
      incoming: math.sin(inT * (math.pi / 2.0)),
    );
  }

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

/// Per-frame gains for the outgoing and incoming engines.
class CrossfadeGains {
  const CrossfadeGains({required this.outgoing, required this.incoming});

  final double outgoing;
  final double incoming;
}
