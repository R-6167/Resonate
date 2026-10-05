import '../../models/dj_analysis.dart';
import '../core/dj_types.dart';
import 'dj_beat_grid_builder.dart';

class DjProfileAnalyzer {
  const DjProfileAnalyzer();
  static const _grid = DjBeatGridBuilder();

  DjTrackProfile build(DjAnalysis analysis) {
    final energy = (analysis.energy ?? 0.5).clamp(0.0, 1.0).toDouble();
    final loudness = (analysis.loudness ?? energy).clamp(0.0, 1.0).toDouble();
    return DjTrackProfile(
      songId: analysis.songId,
      durationMs: analysis.durationMs,
      beatGrid: _grid.fromAnalysis(
        bpm: analysis.hasUsableBpm ? analysis.bpm : null,
        confidence: analysis.bpmConfidence,
        firstBeatMs: analysis.beatOffsetMs,
        durationMs: analysis.durationMs,
      ),
      keyRoot: analysis.hasUsableKey ? analysis.keyRoot : null,
      keyMode: analysis.hasUsableKey ? analysis.keyMode : null,
      keyConfidence: analysis.hasUsableKey ? 0.70 : 0,
      energyCurve: [
        DjEnergyPoint(timeMs: 0, value: energy * 0.8, loudness: loudness),
        DjEnergyPoint(timeMs: analysis.durationMs ?? 0, value: energy * 0.75, loudness: loudness),
      ],
      spectrum: DjSpectralProfile(
        bass: energy * 0.75,
        mids: energy * 0.90,
        highs: loudness * 0.85,
        bassDensity: (energy * 0.65 + 0.18).clamp(0.0, 1.0).toDouble(),
        centroid: 0.35 + loudness * 0.30,
        spectralFlux: energy,
        confidence: analysis.hasUsableEnergy ? 0.30 : 0,
      ),
      transitions: DjTransitionMarkers(
        bestIntroMs: analysis.introHintMs ?? 0,
        bestOutroMs: analysis.durationMs != null && analysis.outroHintMs != null
            ? (analysis.durationMs! - analysis.outroHintMs!).clamp(0, analysis.durationMs!)
            : null,
      ),
      analysisConfidence: analysis.bpmConfidence,
      analysisVersion: analysis.analysisVersion,
    );
  }
}
