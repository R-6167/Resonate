import '../../models/dj_analysis.dart';
import '../core/dj_types.dart';

/// Converts today's cached DjAnalysis into the richer V2 profile.
class DjAnalysisBridge {
  const DjAnalysisBridge();

  DjTrackProfile fromLegacy(DjAnalysis a) {
    final beatGrid = DjBeatGrid(
      bpm: a.hasUsableBpm ? a.bpm : null,
      confidence: a.bpmConfidence,
      firstBeatMs: a.beatOffsetMs,
    );
    final energy = a.energy ?? 0.5;
    return DjTrackProfile(
      songId: a.songId,
      durationMs: a.durationMs,
      beatGrid: beatGrid,
      keyRoot: a.hasUsableKey ? a.keyRoot : null,
      keyMode: a.hasUsableKey ? a.keyMode : null,
      keyConfidence: a.hasUsableKey ? 0.7 : 0,
      energyCurve: [
        if (a.introHintMs != null) DjEnergyPoint(timeMs: a.introHintMs!, value: energy),
        if (a.durationMs != null) DjEnergyPoint(timeMs: (a.durationMs! * 0.5).round(), value: energy),
        if (a.outroHintMs != null && a.durationMs != null)
          DjEnergyPoint(
            timeMs: (a.durationMs! - a.outroHintMs!).clamp(0, a.durationMs!).toInt(),
            value: energy,
          ),
      ],
      transitions: DjTransitionMarkers(
        bestIntroMs: a.introHintMs,
        bestOutroMs: a.durationMs != null && a.outroHintMs != null
            ? (a.durationMs! - a.outroHintMs!).clamp(0, a.durationMs!).toInt()
            : null,
      ),
      analysisConfidence: _confidence(a),
    );
  }

  double _confidence(DjAnalysis a) {
    var score = a.bpmConfidence * 0.45;
    if (a.hasUsableKey) score += 0.20;
    if (a.hasUsableEnergy) score += 0.20;
    if (a.introHintMs != null || a.outroHintMs != null) score += 0.10;
    if (a.durationMs != null) score += 0.05;
    return score.clamp(0.0, 1.0).toDouble();
  }
}
