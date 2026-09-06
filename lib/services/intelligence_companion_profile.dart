import '../providers/intelligence_provider.dart';
import 'intelligence_pattern_store.dart';

/// A compact, local-only interpretation of what Intelligence has learned.
/// It describes evidence-backed tendencies rather than inventing a personality.
class IntelligenceCompanionProfile {
  final String primarySignal;
  final String secondarySignal;
  final String context;
  final String tendency;
  final String explanation;
  final double confidence;
  final double momentum;
  final int learnedEvents;
  final int windowEvents;
  final int completed;
  final int skipped;

  const IntelligenceCompanionProfile({
    required this.primarySignal,
    required this.secondarySignal,
    required this.context,
    required this.tendency,
    required this.explanation,
    required this.confidence,
    required this.momentum,
    required this.learnedEvents,
    required this.windowEvents,
    required this.completed,
    required this.skipped,
  });

  static Future<IntelligenceCompanionProfile> build(IntelligenceProvider intelligence) async {
    final now = DateTime.now();
    final bucket = await IntelligencePatternStore.readBucket(now);
    final stateProfile = await IntelligencePatternStore.readStateProfile();
    final bucketState = IntelligencePatternStore.stateFor(bucket);
    final globalState = IntelligencePatternStore.globalState(stateProfile);
    final globalConfidence = IntelligencePatternStore.stateConfidence(stateProfile);
    final momentum = IntelligencePatternStore.stateMomentum(stateProfile);
    final events = (bucket['events'] as num?)?.toInt() ?? 0;
    final completed = (bucket['completed'] as num?)?.toInt() ?? 0;
    final skipped = (bucket['skipped'] as num?)?.toInt() ?? 0;
    final learned = (stateProfile['total_events'] as num?)?.toInt() ?? 0;
    final completionRate = events == 0 ? 0.0 : completed / events;

    String primary = bucketState;
    String secondary = globalState == 'Learning' ? '' : globalState;
    String tendency;
    String explanation;

    if (intelligence.sessionSkipStreak >= 3) {
      tendency = 'Explore more';
      explanation = 'The current session has several quick exits, so I am widening the next choices.';
    } else if (intelligence.sessionCompletionStreak >= 3) {
      tendency = 'Stay with the flow';
      explanation = 'The current session has a strong run of completed tracks, so I am protecting that flow.';
    } else if (bucketState == 'Familiar flow') {
      tendency = 'Favor proven favorites';
      explanation = IntelligencePatternStore.explanationFor(bucketState, bucket);
    } else if (bucketState == 'Exploration') {
      tendency = 'Open the search';
      explanation = IntelligencePatternStore.explanationFor(bucketState, bucket);
    } else if (globalState != 'Learning' && globalConfidence >= .55) {
      tendency = globalState == 'Familiar flow' ? 'Lean familiar' : globalState == 'Exploration' ? 'Lean exploratory' : 'Stay balanced';
      explanation = 'Longer-term listening patterns are consistent enough to gently guide this session.';
    } else {
      tendency = 'Keep learning';
      explanation = IntelligencePatternStore.explanationFor(bucketState, bucket);
    }

    if (globalState != 'Learning' && globalState != primary && globalConfidence >= .55) {
      secondary = globalState;
    }
    if (secondary.isEmpty && momentum >= .5 && primary != 'Learning') secondary = 'Pattern holding';

    final contextualConfidence = [
      globalConfidence,
      events >= 3 ? (completionRate - .5).abs() * 1.2 : 0.0,
      intelligence.sessionCompletionStreak >= 3 || intelligence.sessionSkipStreak >= 3 ? .78 : 0.0,
    ].reduce((a, b) => a > b ? a : b).clamp(0.0, .97).toDouble();

    final context = bucketState == 'Learning'
        ? 'This time window is still new to me.'
        : 'This pattern shows up around ${_windowLabel(now)}.';

    return IntelligenceCompanionProfile(
      primarySignal: primary,
      secondarySignal: secondary,
      context: context,
      tendency: tendency,
      explanation: explanation,
      confidence: contextualConfidence,
      momentum: momentum,
      learnedEvents: learned,
      windowEvents: events,
      completed: completed,
      skipped: skipped,
    );
  }

  static String _windowLabel(DateTime time) {
    final start = (time.hour ~/ 3) * 3;
    final end = start + 3;
    String hour(int value) {
      final h = value % 24;
      final suffix = h >= 12 ? 'PM' : 'AM';
      final display = h % 12 == 0 ? 12 : h % 12;
      return '$display$suffix';
    }
    return '${hour(start)}–${hour(end)}';
  }
}
