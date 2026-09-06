import '../models/intelligence_mix.dart';
import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import 'database_helper.dart';
import 'intelligence_decision_engine.dart';
import 'intelligence_mix_continuity.dart';
import 'intelligence_mix_memory.dart';
import 'intelligence_seek_memory.dart';

/// Local-only mix intelligence. It does not decode or upload audio. It learns
/// from playback events already recorded by Resonate and uses the same
/// decision engine as Autopilot for generated mixes.
class IntelligenceMixService {
  final DatabaseHelper _database;
  final IntelligenceDecisionEngine _decisionEngine;
  final IntelligenceMixMemory _memory;
  final IntelligenceMixContinuity _continuity;
  final IntelligenceSeekMemory _seekMemory;

  IntelligenceMixService({DatabaseHelper? database, IntelligenceDecisionEngine? decisionEngine, IntelligenceMixMemory? memory, IntelligenceMixContinuity? continuity, IntelligenceSeekMemory? seekMemory})
      : _database = database ?? DatabaseHelper(), _decisionEngine = decisionEngine ?? const IntelligenceDecisionEngine(), _memory = memory ?? IntelligenceMixMemory(), _continuity = continuity ?? IntelligenceMixContinuity(), _seekMemory = seekMemory ?? IntelligenceSeekMemory();

  Future<IntelligenceMixAnalysis?> analyzeLongMix(Song source, {int minimumDurationMinutes = 20}) async {
    final durationMs = source.duration.inMilliseconds;
    if (durationMs < minimumDurationMinutes * 60 * 1000) return null;
    final events = await _database.getRecentListeningEvents(limit: 300);
    final relevant = events.where((event) => event.songId == source.id && event.endedAt != null).toList(growable: false);
    if (relevant.isEmpty) return null;
    const bucketMs = 5 * 60 * 1000;
    final bucketCount = (durationMs / bucketMs).ceil();
    final reached = List<int>.filled(bucketCount, 0);
    final exits = <int, int>{};
    final replays = <int, int>{};
    var completionSum = 0.0;
    for (final event in relevant) {
      completionSum += event.completionRatio.clamp(0.0, 1.0);
      final played = event.durationPlayedMs.clamp(0, durationMs).toInt();
      final lastBucket = played == 0 ? -1 : ((played - 1) / bucketMs).floor();
      for (var bucket = 0; bucket <= lastBucket && bucket < bucketCount; bucket++) reached[bucket]++;
      final exit = event.skipPositionMs;
      if (event.skipped && exit != null && exit > 0) {
        final normalized = (exit / bucketMs).round() * bucketMs;
        exits[normalized] = (exits[normalized] ?? 0) + 1;
      }
    }
    final seekEvents = await _seekMemory.forSong(source.id);
    for (final seek in seekEvents) {
      final toMs = (seek['toMs'] as num?)?.toInt();
      if (toMs == null || toMs < 0 || toMs >= durationMs) continue;
      final bucket = (toMs / bucketMs).floor();
      if (bucket >= 0 && bucket < bucketCount) replays[bucket] = (replays[bucket] ?? 0) + 1;
    }
    final maxReached = reached.reduce((a, b) => a > b ? a : b);
    final preferred = <IntelligenceMixSegment>[];
    var startBucket = -1;
    for (var i = 0; i < reached.length; i++) {
      final strong = (replays[i] ?? 0) >= 2 || (maxReached > 0 && reached[i] >= (maxReached * .55).ceil());
      if (strong && startBucket < 0) startBucket = i;
      else if (!strong && startBucket >= 0) { preferred.add(_segment(startBucket, i, reached, replays, relevant.length, bucketMs, durationMs)); startBucket = -1; }
    }
    if (startBucket >= 0) preferred.add(_segment(startBucket, reached.length, reached, replays, relevant.length, bucketMs, durationMs));
    final strongestExit = exits.isEmpty ? null : exits.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final coverage = preferred.fold<int>(0, (sum, segment) => sum + (segment.endMs - segment.startMs));
    return IntelligenceMixAnalysis(source: source, observations: relevant.length, averageCompletion: completionSum / relevant.length, preferredCoverage: (coverage / durationMs).clamp(0.0, 1.0).toDouble(), preferredSegments: preferred, commonExitPoint: strongestExit == null ? null : Duration(milliseconds: strongestExit));
  }

  IntelligenceMixSegment _segment(int startBucket, int endBucket, List<int> reached, Map<int, int> replays, int observations, int bucketMs, int durationMs) {
    final startMs = (startBucket * bucketMs).clamp(0, durationMs).toInt();
    final endMs = (endBucket * bucketMs).clamp(startMs, durationMs).toInt();
    final listens = reached.sublist(startBucket, endBucket).fold(0, (a, b) => a + b);
    final replayCount = replays.entries.where((entry) => entry.key >= startBucket && entry.key < endBucket).fold(0, (a, b) => a + b.value);
    final span = (endBucket - startBucket).clamp(1, 100000);
    final preference = observations == 0 ? 0.0 : ((listens / (observations * span)) + replayCount * .08).clamp(0.0, 1.0).toDouble();
    return IntelligenceMixSegment(startMs: startMs, endMs: endMs, listens: listens + replayCount, preference: preference);
  }

  Future<IntelligenceMix> generateMix({required List<IntelligenceRecommendation> recommendations, required Song? currentSong, required String sessionMode, int sessionSkipStreak = 0, int sessionCompletionStreak = 0, Map<String, int> sessionArtistCounts = const <String, int>{}, Duration targetDuration = const Duration(minutes: 60), String title = 'Your Resonate Mix'}) async {
    return _generateFrom(recommendations: recommendations, currentSong: currentSong, sessionMode: sessionMode, sessionSkipStreak: sessionSkipStreak, sessionCompletionStreak: sessionCompletionStreak, sessionArtistCounts: sessionArtistCounts, targetDuration: targetDuration, title: title, evolvingFrom: null);
  }

  /// Builds the next edition of an existing mix. Successful journeys keep a
  /// bounded amount of their proven tracks; weak journeys deliberately open
  /// space for new choices. The original mix is never mutated.
  Future<IntelligenceMix> evolveMix({required IntelligenceMix previousMix, required List<IntelligenceRecommendation> recommendations, required Song? currentSong, required String sessionMode, int sessionSkipStreak = 0, int sessionCompletionStreak = 0, Map<String, int> sessionArtistCounts = const <String, int>{}, Duration? targetDuration}) async {
    final assessment = await _continuity.evaluate(previousMix);
    if (assessment != null) await _continuity.remember(assessment);
    final score = (assessment?['score'] as num?)?.toDouble() ?? await _continuity.continuityPrior();
    final priorIds = previousMix.songs.map((song) => song.id).toSet();
    final adjusted = recommendations.map((item) {
      final inPrevious = priorIds.contains(item.song.id);
      final delta = inPrevious ? (score >= .65 ? .10 : score <= .35 ? -.12 : .02) : (score <= .35 ? .06 : 0.0);
      return IntelligenceRecommendation(song: item.song, score: item.score + delta, confidence: item.confidence, reason: item.reason, decision: item.decision, sessionReason: item.sessionReason);
    }).toList(growable: false);
    final title = score >= .65 ? '${previousMix.title} • Refined' : score <= .35 ? '${previousMix.title} • Reimagined' : '${previousMix.title} • Evolved';
    return _generateFrom(recommendations: adjusted, currentSong: currentSong, sessionMode: sessionMode, sessionSkipStreak: sessionSkipStreak, sessionCompletionStreak: sessionCompletionStreak, sessionArtistCounts: sessionArtistCounts, targetDuration: targetDuration ?? previousMix.targetDuration, title: title, evolvingFrom: score);
  }

  Future<IntelligenceMix> _generateFrom({required List<IntelligenceRecommendation> recommendations, required Song? currentSong, required String sessionMode, required int sessionSkipStreak, required int sessionCompletionStreak, required Map<String, int> sessionArtistCounts, required Duration targetDuration, required String title, required double? evolvingFrom}) async {
    final songs = <Song>[];
    final selectedIds = <String>{if (currentSong != null) currentSong.id};
    final targetMs = targetDuration.inMilliseconds;
    final continuityPrior = await _continuity.continuityPrior();
    var totalMs = 0;
    var safety = 0;
    while (totalMs < targetMs && safety < 80) {
      safety++;
      final next = await _decisionEngine.chooseSequence(recommendations: _continuityAdjustedRecommendations(recommendations, continuityPrior), queuedIds: selectedIds, currentSong: songs.isEmpty ? currentSong : songs.last, sessionMode: sessionMode, sessionSkipStreak: sessionSkipStreak, sessionCompletionStreak: sessionCompletionStreak, sessionArtistCounts: sessionArtistCounts, count: 1);
      if (next.isEmpty) break;
      final song = next.first;
      if (selectedIds.contains(song.id)) break;
      songs.add(song); selectedIds.add(song.id); totalMs += song.duration.inMilliseconds;
    }
    final reason = _mixReason(sessionMode: sessionMode, sessionSkipStreak: sessionSkipStreak, sessionCompletionStreak: sessionCompletionStreak, count: songs.length, continuityPrior: continuityPrior, evolvingFrom: evolvingFrom);
    final description = songs.isEmpty ? 'I need a little more listening evidence before I can build this mix.' : evolvingFrom == null ? '${songs.length} tracks shaped by your long-term memory, recent listening and previous mix journeys.' : '${songs.length} tracks refined from how you actually listened to the previous edition.';
    final mix = IntelligenceMix(id: 'mix_${DateTime.now().microsecondsSinceEpoch}', title: title, description: description, songs: List.unmodifiable(songs), targetDuration: targetDuration, createdAt: DateTime.now(), reason: reason);
    await _memory.remember(mix);
    return mix;
  }

  List<IntelligenceRecommendation> _continuityAdjustedRecommendations(List<IntelligenceRecommendation> recommendations, double prior) {
    if (recommendations.isEmpty || (prior - .5).abs() < .08) return recommendations;
    final factor = (prior - .5) * .20;
    return recommendations.map((item) => IntelligenceRecommendation(song: item.song, score: item.score + factor * item.confidence.clamp(0.0, 1.0), confidence: item.confidence, reason: item.reason, decision: item.decision, sessionReason: item.sessionReason)).toList(growable: false);
  }

  Future<Map<String, dynamic>?> evaluateMix(IntelligenceMix mix) async { final assessment = await _continuity.evaluate(mix); if (assessment != null) await _continuity.remember(assessment); return assessment; }
  Future<List<Map<String, dynamic>>> recentMixContinuity() => _continuity.recent();
  Future<List<Map<String, dynamic>>> recentGeneratedMixes() => _memory.recent();

  String _mixReason({required String sessionMode, required int sessionSkipStreak, required int sessionCompletionStreak, required int count, required double continuityPrior, required double? evolvingFrom}) {
    if (count == 0) return 'Not enough confident choices yet.';
    if (evolvingFrom != null && evolvingFrom >= .65) return 'Refining a mix you tended to stay with.';
    if (evolvingFrom != null && evolvingFrom <= .35) return 'Reimagining a mix that did not quite land.';
    if (continuityPrior >= .72) return 'Building on mix flows you have tended to stay with.';
    if (continuityPrior <= .35) return 'Trying a different path after recent mixes did not quite land.';
    if (sessionSkipStreak >= 2) return 'A little more exploration after your recent skips.';
    if (sessionCompletionStreak >= 2) return 'Keeping the flow because you have been finishing tracks.';
    if (sessionMode == 'Exploring') return 'A balanced discovery mix for this session.';
    if (sessionMode == 'Familiar flow') return 'A familiar flow built around patterns you tend to keep.';
    return 'A balanced mix from your current Resonate memory.';
  }
}