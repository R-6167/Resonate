import 'package:flutter/foundation.dart';

import '../providers/intelligence_mix_controller.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../services/intelligence_settings_store.dart';
import '../services/local_intent_parser.dart';

class CompanionCommandResult {
  final bool ok;
  final String message;
  const CompanionCommandResult({required this.ok, required this.message});
}

/// Runs structured companion intents against existing local providers only.
class CompanionCommandExecutor {
  final MusicProvider music;
  final IntelligenceProvider intelligence;
  final IntelligenceMixController mixes;

  CompanionCommandExecutor({
    required this.music,
    required this.intelligence,
    required this.mixes,
  });

  Future<CompanionCommandResult> execute(CompanionIntent intent) async {
    if (!intelligence.isEnabled &&
        intent.action != CompanionAction.explainSession) {
      return const CompanionCommandResult(
        ok: false,
        message: 'Intelligence is off. Enable it in Settings to use Ask Resonate actions.',
      );
    }

    try {
      switch (intent.action) {
        case CompanionAction.explainSession:
          return CompanionCommandResult(
            ok: true,
            message: intelligence.sessionSummary.isNotEmpty
                ? intelligence.sessionSummary
                : 'Not enough listening in this session yet for a clear read.',
          );

        case CompanionAction.increaseExploration:
          final cur = await IntelligenceSettingsStore.exploration();
          final next = (cur + 15).clamp(0, 100);
          await IntelligenceSettingsStore.setExploration(next);
          await intelligence.refreshRecommendations();
          return CompanionCommandResult(
            ok: true,
            message: 'Exploration up to $next%. I’ll lean toward less-played local picks.',
          );

        case CompanionAction.decreaseExploration:
          final cur = await IntelligenceSettingsStore.exploration();
          final next = (cur - 15).clamp(0, 100);
          await IntelligenceSettingsStore.setExploration(next);
          await intelligence.refreshRecommendations();
          return CompanionCommandResult(
            ok: true,
            message: 'Exploration down to $next%. I’ll stick closer to familiar patterns.',
          );

        case CompanionAction.avoidArtist:
          final song = music.currentSong;
          if (song == null) {
            return const CompanionCommandResult(
              ok: false,
              message: 'Nothing is playing — open a track first, then avoid that artist.',
            );
          }
          await intelligence.rateRecommendation(song.id, false);
          await intelligence.avoidArtist(song.artist);
          return CompanionCommandResult(
            ok: true,
            message: 'I’ll downrank ${song.artist} for a while based on this session.',
          );

        case CompanionAction.similarToCurrent:
          final current = music.currentSong;
          final recs = intelligence.recommendations;
          if (recs.isEmpty) {
            await intelligence.refreshRecommendations();
          }
          final list = intelligence.recommendations.map((r) => r.song).toList();
          if (list.isEmpty) {
            return const CompanionCommandResult(
              ok: false,
              message: 'No similar picks yet — play a bit more so local patterns can form.',
            );
          }
          // Prefer same artist when possible.
          final preferred = current == null
              ? list
              : [
                  ...list.where((s) => s.artist == current.artist),
                  ...list.where((s) => s.artist != current.artist),
                ];
          await music.playSong(preferred.first, queue: preferred, startIndex: 0);
          return CompanionCommandResult(
            ok: true,
            message: current == null
                ? 'Started a local similar mix from your top recommendations.'
                : 'More like «${current.title}» from local transitions and affinity.',
          );

        case CompanionAction.createMix:
          final title = switch (intent.mood) {
            'relaxing' => 'Calmer local mix',
            'energetic' => 'Higher-energy local mix',
            'familiar' => 'Familiar flow mix',
            'explore' => 'Exploratory local mix',
            _ => 'Your Resonate mix',
          };
          if (intent.mood == 'explore') {
            final cur = await IntelligenceSettingsStore.exploration();
            await IntelligenceSettingsStore.setExploration((cur + 10).clamp(0, 100));
          } else if (intent.mood == 'familiar' || intent.mood == 'relaxing') {
            final cur = await IntelligenceSettingsStore.exploration();
            await IntelligenceSettingsStore.setExploration((cur - 10).clamp(0, 100));
          }
          await intelligence.refreshRecommendations();
          final mix = await mixes.generateMix(title: title);
          if (mix == null || mix.songs.isEmpty) {
            return CompanionCommandResult(
              ok: false,
              message: 'Couldn’t build «$title» yet — need more library signals or recommendations.',
            );
          }
          await music.playSong(mix.songs.first, queue: mix.songs, startIndex: 0);
          return CompanionCommandResult(
            ok: true,
            message: 'Started «${mix.title}» (${mix.songs.length} tracks). ${mix.reason}',
          );

        case CompanionAction.evolveMix:
          final mix = await mixes.evolveCurrentMix();
          if (mix == null) {
            return const CompanionCommandResult(
              ok: false,
              message: 'No active mix to evolve — create one first.',
            );
          }
          if (mix.songs.isNotEmpty) {
            await music.playSong(mix.songs.first, queue: mix.songs, startIndex: 0);
          }
          return CompanionCommandResult(
            ok: true,
            message: 'Evolved to «${mix.title}» (edition ${mix.edition}).',
          );

        case CompanionAction.playTopRecommendation:
          final recs = intelligence.recommendations;
          if (recs.isEmpty) {
            return const CompanionCommandResult(
              ok: false,
              message: 'No recommendations ready yet.',
            );
          }
          final songs = recs.map((r) => r.song).toList();
          await music.playSong(songs.first, queue: songs, startIndex: 0);
          return CompanionCommandResult(
            ok: true,
            message: 'Playing «${songs.first.title}» — ${recs.first.reason}',
          );

        case CompanionAction.unknown:
          return const CompanionCommandResult(
            ok: false,
            message: 'Try a command below — e.g. more like this, calmer mix, or more adventurous.',
          );
      }
    } catch (e) {
      debugPrint('Companion command failed: $e');
      return CompanionCommandResult(ok: false, message: 'Something went wrong: $e');
    }
  }
}
