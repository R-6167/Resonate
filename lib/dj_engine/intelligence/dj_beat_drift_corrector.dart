class DjBeatDriftDecision {
  final double speed;
  final int holdMs;
  final int driftMs;

  const DjBeatDriftDecision({
    required this.speed,
    required this.holdMs,
    required this.driftMs,
  });
}

/// Conservative runtime phase correction. It never chooses a beat or seeks;
/// it only decides whether a tiny temporary speed adjustment is safe.
class DjBeatDriftCorrector {
  const DjBeatDriftCorrector();

  DjBeatDriftDecision? decide({
    required int driftMs,
    required double bpm,
    required double baseSpeed,
    double maxCorrectionPercent = 0.6,
  }) {
    if (bpm < 40 || bpm > 240) return null;
    if (baseSpeed <= 0) return null;

    final absDrift = driftMs.abs();
    final periodMs = 60000.0 / bpm;
    final toleranceMs = periodMs.clamp(55.0, 90.0);
    if (absDrift <= 18 || absDrift > toleranceMs) return null;

    // If the incoming track is ahead (positive drift), slow it briefly.
    // If it is behind (negative drift), speed it up briefly.
    final correction = maxCorrectionPercent.clamp(0.1, 1.0) / 100.0;
    final multiplier = driftMs > 0 ? 1.0 - correction : 1.0 + correction;
    final speed = (baseSpeed * multiplier).clamp(0.5, 2.0).toDouble();

    return DjBeatDriftDecision(
      speed: speed,
      holdMs: 650,
      driftMs: driftMs,
    );
  }
}
