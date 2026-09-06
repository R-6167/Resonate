import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import 'database_helper.dart';
import 'intelligence_pattern_store.dart';
import 'intelligence_settings_store.dart';

/// Chooses the next track from Intelligence's ranked evidence.
class IntelligenceDecisionEngine {
  const IntelligenceDecisionEngine();

  String _artistKey(String? value) {
    final raw = value?.trim().toLowerCase() ?? '';
    const unknown = <String>{'', 'unknown', 'unknown artist', 'unknown_artist', '<unknown>', 'n/a', 'na', 'none', 'null', 'various artists', 'various artist'};
    return unknown.contains(raw) ? '' : raw;
  }

  Future<List<Song>> chooseSequence({
    required List<IntelligenceRecommendation> recommendations,
    required Set<String> queuedIds,
    required Song? currentSong,
    required String sessionMode,
    int sessionSkipStreak = 0,
    int sessionCompletionStreak = 0,
    Map<String, int> sessionArtistCounts = const <String, int>{},
    int count = 2,
  }) async {
    if (count <= 0 || recommendations.isEmpty) return const <Song>[];
    final threshold = await IntelligenceSettingsStore.confidenceThreshold();
    final exploration = (await IntelligenceSettingsStore.exploration()) / 100.0;
    final allowArtistRepeat = await IntelligenceSettingsStore.artistRepeat();
    final database = DatabaseHelper();
    final songs = await database.getAllSongs();
    final recentEvents = await database.getRecentListeningEvents(limit: 200);
    final songsById = {for (final song in songs) song.id: song};
    await IntelligencePatternStore.learnFromRecentEvents(recentEvents, songsById);
    final pattern = await IntelligencePatternStore.readBucket(DateTime.now());
    final patternSongs = _counts(pattern['songs']);
    final patternArtists = _counts(pattern['artists']);
    final patternEvents = (pattern['events'] as num?)?.toInt() ?? 0;
    final patternCompleted = (pattern['completed'] as num?)?.toInt() ?? 0;
    final patternCompletionRate = patternEvents == 0 ? 0.0 : patternCompleted / patternEvents;
    final patternState = IntelligencePatternStore.stateFor(pattern);

    final pool = recommendations.where((r) => r.confidence >= threshold).where((r) => r.song.id != currentSong?.id).where((r) => !queuedIds.contains(r.song.id)).toList(growable: false);
    if (pool.isEmpty) return const <Song>[];

    final currentArtist = _artistKey(currentSong?.artist);
    final selected = <Song>[];
    final selectedArtists = <String>{};
    final explorationPressure = sessionSkipStreak.clamp(0, 4) / 4.0;
    final continuityPressure = sessionCompletionStreak.clamp(0, 4) / 4.0;

    double utility(IntelligenceRecommendation r, int rank) {
      final artist = _artistKey(r.song.artist);
      final sessionArtistCount = artist.isEmpty ? 0 : (sessionArtistCounts[artist] ?? 0);
      final sessionFatigue = sessionArtistCount >= 2 ? (sessionArtistCount - 1) * 1.1 : 0.0;
      final sameCurrentArtist = artist.isNotEmpty && artist == currentArtist;
      final historicalSongWeight = patternSongs[r.song.id] ?? 0;
      final historicalArtistWeight = artist.isEmpty ? 0 : (patternArtists[artist] ?? 0);
      final historicalSongBoost = historicalSongWeight > 0 ? (0.55 + (historicalSongWeight.clamp(0, 8) / 8.0)) * (1.0 - exploration * .65) : 0.0;
      final historicalArtistBoost = historicalArtistWeight > 0 ? (0.35 + (historicalArtistWeight.clamp(0, 8) / 8.0)) * (1.0 - exploration * .55) : 0.0;
      var value = r.score * (1.0 - exploration) + exploration * (1.0 - rank / pool.length) * 3.0 + r.confidence * 2.0;
      value += historicalSongBoost + historicalArtistBoost;
      if (patternCompletionRate >= .70 && patternEvents >= 3) value += historicalSongBoost * .45;
      if (patternState == 'Familiar flow' && historicalSongWeight > 0) {
        value += (1.0 - exploration) * .9;
      } else if (patternState == 'Exploration' && historicalSongWeight == 0) {
        value += exploration * 1.1;
      } else if (patternState == 'Balanced') {
        value += .15;
      }
      if (sessionMode == 'Exploring') value += exploration * 1.5;
      else if (sessionMode == 'Familiar flow') value += (1.0 - exploration) * 1.0;
      if (explorationPressure > 0) {
        value += explorationPressure * (artist.isEmpty ? .15 : -sessionArtistCount * .7);
        if (sameCurrentArtist) value -= explorationPressure * 1.0;
      }
      if (continuityPressure > 0 && sessionArtistCount > 0) value += continuityPressure * 1.25;
      value -= sessionFatigue * (0.5 + explorationPressure);
      return value;
    }

    final ranked = <({IntelligenceRecommendation recommendation, int rank, double utility})>[];
    for (var i = 0; i < pool.length; i++) {
      final recommendation = pool[i];
      ranked.add((recommendation: recommendation, rank: i, utility: utility(recommendation, i)));
    }
    ranked.sort((a, b) => b.utility.compareTo(a.utility));
    for (final item in ranked) {
      if (selected.length >= count) break;
      final artist = _artistKey(item.recommendation.song.artist);
      final repeatsCurrent = artist.isNotEmpty && artist == currentArtist;
      final repeatsSelected = artist.isNotEmpty && selectedArtists.contains(artist);
      if (!allowArtistRepeat && (repeatsCurrent || repeatsSelected)) continue;
      selected.add(item.recommendation.song);
      if (artist.isNotEmpty) selectedArtists.add(artist);
    }
    if (selected.length < count) {
      for (final item in ranked) {
        if (selected.length >= count) break;
        if (selected.any((song) => song.id == item.recommendation.song.id)) continue;
        selected.add(item.recommendation.song);
      }
    }
    return selected;
  }

  Map<String, int> _counts(dynamic value) {
    if (value is! Map) return <String, int>{};
    return value.map((key, item) => MapEntry(key.toString(), (item as num?)?.toInt() ?? 0));
  }
}
