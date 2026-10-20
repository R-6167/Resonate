import '../models/intelligence_mix.dart';

/// Describes how a remembered mix should evolve without replacing the
/// original mix. All values are bounded so one listening journey cannot
/// dominate future decisions.
class IntelligenceEvolvingMix {
  final IntelligenceMix mix;
  final double continuityScore;
  final double adjustment;
  final String explanation;

  const IntelligenceEvolvingMix({
    required this.mix,
    required this.continuityScore,
    required this.adjustment,
    required this.explanation,
  });

  bool get shouldKeepFlow => continuityScore >= .65;
  bool get shouldExplore => continuityScore <= .35;
}
