import '../models/intelligence_mix.dart';
import '../models/intelligence_recommendation.dart';
import '../models/listening_event.dart';
import '../models/song.dart';
import 'database_helper.dart';
import 'intelligence_decision_engine.dart';
import 'intelligence_settings_store.dart';

/// Local-only mix intelligence. It does not decode or upload audio. It learns
/// from playback events already recorded by Resonate and uses the same
/// decision engine as Autopilot for generated mixes.
class IntelligenceMixService {
  final DatabaseHelper _database;
  final IntelligenceDecisionEngine _decisionEngine;

  IntelligenceMixService({
    DatabaseHelper? database,
    IntelligenceDecisionEngine? decisionEngine,
  })  : _database = database ?? DatabaseHelper(),
        _decisionEngine = decisionEngine ?? const IntelligenceDecisionEngine();

  /// Analyzes a long audio item as a behavioral listening map.
  ///
  /// Today Resonate records where a listener stopped and how much of the item
  /// they consumed. That is enough to identify repeatedly reached sections and
  /// common exit points without pretending we can identify embedded tracks in
  /// a DJ mix. True embedded-track recognition can be layered on later.
  Future<IntelligenceMixAnalysis?> analyzeLongMix(
    Song source, {
    int minimumDurationMinutes = 20,
  }) async {
    final durationMs = source.duration.inMilliseconds;
    if (durationMs < minimumDurationMinutes * 60 * 1000) return null;

    final events = await _database.getRecentListeningEvents(limit: 300);
    final relevant = events
        .where((event) => event.songId == source.id && event.endedAt != null)
        .toList(growable: false);
    if (relevant.isEmpty) return null;

    const bucketMs = 5 * 60 * 1000;
    final bucketCount = (durationMs / bucketMs).ceil();
    final reached = List<int>.filled(bucketCount, 0);
    final exits = <int, int>{};
    var completionSum = 0.0;

    for (final event in relevant) {
      completionSum += event.completionRatio.clamp(0.0, 1.0);
      final played = event.durationPlayedMs.clamp(0, durationMs);
      final lastBucket = played == 0 ? -1 : ((played - 1) / bucketMs).floor();
      for (var bucket = 0; bucket <= lastBucket && bucket < bucketCount; bucket++) {
        reached[bucket]++;
      }
      final exit = event.skipPositionMs;
      if (event.skipped && exit != null && exit > 0) {
        final normalized = (exit / bucketMs).round() * bucketMs;
        exits[normalized] = (exits[normalized] ?? 0) + 1;
      }
    }

    final maxReached = reached.reduce((a, b) => a > b ? a : b);
    final preferred = <IntelligenceMixSegment>[];
    var startBucket = -1;
    for (var i = 0; i < reached.length; i++) {
      final strong = maxReached > 0 && reached[i] >= (maxReached * .55).ceil();
      if (strong && startBucket < 0) {
        startBucket = i;
      } else if (!strong && startBucket >= 0) {
        preferred.add(_segment(startBucket, i, reached, relevant.length, bucketMs, durationMs));
        startBucket = -1;
      }
    }
    if (startBucket >= 0) {
      preferred.add(_segment(startBucket, reached.length, reached, relevant.length, bucketMs, durationMs));
    }

    final strongestExit = exits.isEmpty
        ? null
        : exits.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final coverage = preferred.fold<int>(0, (sum, segment) => sum + (segment.endMs - segment.startMs));

    return IntelligenceMixAnalysis(
      source: source,
      observations: relevant.length,
      averageCompletion: completionSum / relevant.length,
      preferredCoverage: (coverage / durationMs).clamp(0.0, 1.0).toDouble(),
      preferredSegments: preferred,
      commonExitPoint: strongestExit == null ? null : Duration(milliseconds: strongestExit),
    );
  }

  IntelligenceMixSegment _segment(
    int startBucket,
    int endBucket,
    List<int> reached,
    int observations,
    int bucketMs,
    int durationMs,
  ) {
    final startMs = (startBucket * bucketMs).clamp(0, durationMs);
    final endMs = (endBucket * bucketMs).clamp(startMs, durationMs);
    final listens = reached.sublist(startBucket, endBucket).fold(0, (a, b) => a + b);
    final span = (endBucket - startBucket).clamp(1, 100000);
    final returns = (listens / span).round();
    final preference = observations == 0 ? 0.0 : (listens / (observations * span)).clamp(0.0, 1.0).toDouble();
    return IntelligenceMixSegment(
      startMs: startMs,
      endMs: endMs,
      listens: listens,
      returns: returns,
      preference: preference,
    );
  }

  /// Generates a fresh local mixtape from Intelligence recommendations.
  ///
  /// This is deliberately a dynamic sequence rather than a permanently saved
  /// playlist. Calling it again can produce a different mix as the user's
  /// memory and current session change.
  Future<IntelligenceMix> generateMix({
    required List<IntelligenceRecommendation> recommendations,
    required Song? currentSong,
    required String sessionMode,
    int sessionSkipStreak = 0,
    int sessionCompletionStreak = 0,
    Map<String, int> sessionArtistCounts = const <String, int>{},
    Duration targetDuration = const Duration(minutes: 60),
    String title = 'Your Resonate Mix',
  }) async {
    final songs = <Song>[];
    final selectedIds = <String>{currentSong?.id};
    final targetMs = targetDuration.inMilliseconds;
    var totalMs = 0;
    var safety = 0;

    while (totalMs < targetMs && safety < 80) {
      safety++;
      final next = await _decisionEngine.chooseSequence(
        recommendations: recommendations,
        queuedIds: selectedIds,
        currentSong: songs.isEmpty ? currentSong : songs.last,
        sessionMode: sessionMode,
        sessionSkipStreak: sessionSkipStreak,
        sessionCompletionStreak: sessionCompletionStreak,
        sessionArtistCounts: sessionArtistCounts,
        count: 1,
      );
      if (next.isEmpty) break;
      final song = next.first;
      if (selectedIds.contains(song.id)) break;
      songs.add(song);
      selectedIds.add(song.id);
      totalMs += song.duration.inMilliseconds;
    }

    final reason = _mixReason(
      sessionMode: sessionMode,
      sessionSkipStreak: sessionSkipStreak,
      sessionCompletionStreak: sessionCompletionStreak,
      count: songs.length,
    );
    final description = songs.isEmpty
        ? 'I need a little more listening evidence before I can build this mix.'
        : '${songs.length} tracks shaped by your long-term memory and what you seem to want right now.';

    return IntelligenceMix(
      id: 'mix_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      description: description,
      songs: List.unmodifiable(songs),
      targetDuration: targetDuration,
      createdAt: DateTime.now(),
      reason: reason,
    );
  }

  String _mixReason({
    required String sessionMode,
    required int sessionSkipStreak,
    required int sessionCompletionStreak,
    required int count,
  }) {
    if (count == 0) return 'Not enough confident choices yet.';
    if (sessionSkipStreak >= 2) return 'A little more exploration after your recent skips.';
    if (sessionCompletionStreak >= 2) return 'Keeping the flow because you have been finishing tracks.';
    if (sessionMode == 'Exploring') return 'A balanced discovery mix for this session.';
    if (sessionMode == 'Familiar flow') return 'A familiar flow built around patterns you tend to keep.';
    return 'A balanced mix from your current Resonate memory.';
  }
}
