import '../core/dj_types.dart';

class DjBeatGridBuilder {
  const DjBeatGridBuilder();

  DjBeatGrid fromAnalysis({
    required double? bpm,
    required double confidence,
    int? firstBeatMs,
    int? durationMs,
  }) {
    return DjBeatGrid(
      bpm: bpm,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      firstBeatMs: firstBeatMs,
      beatsPerBar: 4,
      beatsPerPhrase: 16,
    );
  }
}
