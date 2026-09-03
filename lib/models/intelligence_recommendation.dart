import 'song.dart';

class IntelligenceRecommendation {
  final Song song;
  final double score;
  final String reason;

  const IntelligenceRecommendation({
    required this.song,
    required this.score,
    required this.reason,
  });
}
