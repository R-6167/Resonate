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
  final double familiarityAffinity;
  final double explorationAffinity;
  final double skipSensitivity;
  final double artistDiversity;
  final double feedbackAlignment;

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
    required this.familiarityAffinity,
    required this.explorationAffinity,
    required this.skipSensitivity,
    required this.artistDiversity,
    required this.feedbackAlignment,
  });

  static Future<Map<String, double>> readPreferenceSignals() async {
    final bucket = await IntelligencePatternStore.readBucket(DateTime.now());
    final profile = await IntelligencePatternStore.readStateProfile();
    final events = (bucket['events'] as num?)?.toInt() ?? 0;
    final completed = (bucket['completed'] as num?)?.toInt() ?? 0;
    final skipped = (bucket['skipped'] as num?)?.toInt() ?? 0;
    final completionRate = events == 0 ? .5 : completed / events;
    final skipRate = events == 0 ? .0 : skipped / events;
    final songs = _counts(bucket['songs']);
    final artists = _counts(bucket['artists']);
    final totalArtistWeight = artists.values.fold<int>(0, (sum, value) => sum + value);
    final distinctArtists = artists.keys.length;
    final concentration = totalArtistWeight == 0 ? 0.0 : (artists.values.fold<int>(0, (sum, value) => sum + value * value) / (totalArtistWeight * totalArtistWeight)).clamp(0.0, 1.0).toDouble();
    final diversity = (1.0 - concentration).clamp(0.0, 1.0).toDouble();
    final learned = (profile['total_events'] as num?)?.toInt() ?? 0;
    final evidence = (events / 12.0).clamp(0.0, 1.0);
    final familiarity = ((completionRate * .65) + ((songs.length.clamp(0, 12) / 12.0) * .35)) * evidence;
    final exploration = ((skipRate * .70) + (1.0 - (songs.length.clamp(0, 12) / 12.0)) * .30) * evidence;
    final skipSensitivity = (skipRate * .75 + (learned >= 12 ? .25 : 0.0)).clamp(0.0, 1.0).toDouble();
    return <String, double>{
      'familiarity': familiarity.clamp(0.0, 1.0).toDouble(),
      'exploration': exploration.clamp(0.0, 1.0).toDouble(),
      'skipSensitivity': skipSensitivity,
      'artistDiversity': (diversity * (distinctArtists >= 2 ? 1.0 : .5)).clamp(0.0, 1.0).toDouble(),
    };
  }

  static Future<IntelligenceCompanionProfile> build(IntelligenceProvider intelligence) async {
    final now = DateTime.now();
    final bucket = await IntelligencePatternStore.readBucket(now);
    final stateProfile = await IntelligencePatternStore.readStateProfile();
    final signals = await readPreferenceSignals();
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

    if (globalState != 'Learning' && globalState != primary && globalConfidence >= .55) secondary = globalState;
    if (secondary.isEmpty && momentum >= .5 && primary != 'Learning') secondary = 'Pattern holding';

    final contextualConfidence = [
      globalConfidence,
      events >= 3 ? (completionRate - .5).abs() * 1.2 : 0.0,
      intelligence.sessionCompletionStreak >= 3 || intelligence.sessionSkipStreak >= 3 ? .78 : 0.0,
    ].reduce((a, b) => a > b ? a : b).clamp(0.0, .97).toDouble();
    final context = bucketState == 'Learning' ? 'This time window is still new to me.' : 'This pattern shows up around ${_windowLabel(now)}.';

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
      familiarityAffinity: signals['familiarity'] ?? 0,
      explorationAffinity: signals['exploration'] ?? 0,
      skipSensitivity: signals['skipSensitivity'] ?? 0,
      artistDiversity: signals['artistDiversity'] ?? 0,
      feedbackAlignment: intelligence.feedbackAlignment,
    );
  }

  static Map<String, int> _counts(dynamic value) {
    if (value is! Map) return <String, int>{};
    return value.map((key, item) => MapEntry(key.toString(), (item as num?)?.toInt() ?? 0));
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
