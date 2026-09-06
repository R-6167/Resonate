import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import 'intelligence_settings_store.dart';

/// Chooses the next track from Intelligence's ranked evidence.
///
/// This layer deliberately does not play audio or mutate the queue. It turns
/// recommendations into a session-aware decision so Autopilot does not simply
/// take the first two ranked rows every time.
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

    // Recommendation.score is the learned evidence. Confidence protects
    // Autopilot from acting on thin evidence. Exploration then deliberately
    // lifts lower-ranked, well-supported alternatives instead of making the
    // exploration setting cosmetic.
    double utility(IntelligenceRecommendation r, int rank) {
      final evidence = r.score * (1.0 - exploration);
      final explorationLift = exploration * (1.0 - rank / pool.length) * 3.0;
      final confidenceLift = r.confidence * 2.0;
      final modeLift = sessionMode == 'Exploring'
          ? exploration * 1.5
          : sessionMode == 'Familiar flow'
              ? (1.0 - exploration) * 1.0
              : .0;
      return evidence + explorationLift + confidenceLift + modeLift;
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
