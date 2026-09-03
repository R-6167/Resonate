import 'song.dart';

class IntelligenceRecommendation {
  final Song song;
  final double score;
  final double confidence;
  final String reason;
  final String decision;

  const IntelligenceRecommendation({
    required this.song,
    required this.score,
    required this.reason,
    this.confidence = 0.0,
    this.decision = 'suggest',
  });

  String get confidenceLabel {
    if (confidence >= 0.85) return 'Very confident';
    if (confidence >= 0.65) return 'Confident';
    if (confidence >= 0.45) return 'Possible';
    return 'Exploring';
  }
}
