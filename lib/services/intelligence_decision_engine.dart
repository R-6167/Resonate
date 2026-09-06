import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import 'intelligence_settings_store.dart';

/// Chooses the next track from Intelligence's ranked evidence.
///
/// This layer deliberately does not play audio or mutate the queue. It turns
/// recommendations into a session-aware decision so Autopilot does not simply
/// take the first ranked rows every time.
class IntelligenceDecisionEngine {
  const IntelligenceDecisionEngine();

  String _artistKey(String? value) {
    final raw = value?.trim().toLowerCase() ?? '';
    const unknown = <String>{
      '',
      'unknown',
      'unknown artist',
      'unknown_artist',
      '<unknown>',
      'n/a',
      'na',
      'none',
      'null',
      'various artists',
      'various artist',
    };
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

    final pool = recommendations
        .where((r) => r.confidence >= threshold)
        .where((r) => r.song.id != currentSong?.id)
        .where((r) => !queuedIds.contains(r.song.id))
        .toList(growable: false);
    if (pool.isEmpty) return const <Song>[];

    final currentArtist = _artistKey(currentSong?.artist);
    final selected = <Song>[];
    final selectedArtists = <String>{};

    // Session signals deliberately have a short memory. A run of skips opens
    // the search, while a run of completed tracks rewards continuity. The
    // effect is bounded so one unusual burst cannot permanently steer the user.
    final explorationPressure = sessionSkipStreak.clamp(0, 4) / 4.0;
    final continuityPressure = sessionCompletionStreak.clamp(0, 4) / 4.0;

    double utility(IntelligenceRecommendation r, int rank) {
      final artist = _artistKey(r.song.artist);
      final sessionArtistCount = artist.isEmpty ? 0 : (sessionArtistCounts[artist] ?? 0);
      final sessionFatigue = sessionArtistCount >= 2 ? (sessionArtistCount - 1) * 1.1 : 0.0;
      final sameCurrentArtist = artist.isNotEmpty && artist == currentArtist;

      var value = r.score * (1.0 - exploration);
      value += exploration * (1.0 - rank / pool.length) * 3.0;
      value += r.confidence * 2.0;

      if (sessionMode == 'Exploring') {
        value += exploration * 1.5;
      } else if (sessionMode == 'Familiar flow') {
        value += (1.0 - exploration) * 1.0;
      }

      // When the user is skipping repeatedly, prefer a genuinely different
      // direction. When they are completing repeatedly, preserve continuity.
      if (explorationPressure > 0) {
        value += explorationPressure * (artist.isEmpty ? .15 : -sessionArtistCount * .7);
        if (sameCurrentArtist) value -= explorationPressure * 1.0;
      }
      if (continuityPressure > 0 && sessionArtistCount > 0) {
        value += continuityPressure * 1.25;
      }
      value -= sessionFatigue * (0.5 + explorationPressure);
      return value;
    }

    final ranked = <({IntelligenceRecommendation recommendation, int rank, double utility})>[];
    for (var i = 0; i < pool.length; i++) {
      final recommendation = pool[i];
      ranked.add((
        recommendation: recommendation,
        rank: i,
        utility: utility(recommendation, i),
      ));
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

    // Diversity is a preference, not a hard failure mode. If the library is
    // narrow, fill the remaining slots rather than starving Autopilot.
    if (selected.length < count) {
      for (final item in ranked) {
        if (selected.length >= count) break;
        if (selected.any((song) => song.id == item.recommendation.song.id)) continue;
        selected.add(item.recommendation.song);
      }
    }
    return selected;
  }
}
