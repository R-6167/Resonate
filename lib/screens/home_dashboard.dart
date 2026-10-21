import 'package:flutter/material.dart';
import '../ui/resonate_glass.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import '../providers/intelligence_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../providers/listening_history_provider.dart';
import '../services/playback_authority.dart';
import '../widgets/dj_mode_status_chip.dart';
import '../widgets/evolving_mix_card.dart';
import '../widgets/autopilot_home_card.dart';
import '../widgets/resonate_logo.dart';
import '../widgets/resonate_mode_chip.dart';
import '../widgets/mode_player_density.dart';
import '../modes/providers/mode_provider.dart';
import '../widgets/mode_shelf_card.dart';
import '../widgets/driving_suggestion_banner.dart';
import '../navigation/shell_nav.dart';

String _homeFormatClock(int ms) {
  final totalSec = (ms / 1000).floor().clamp(0, 24 * 3600);
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _homeFormatHours(int ms) {
  final minutes = Duration(milliseconds: ms).inMinutes;
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final music = context.read<MusicProvider>();
    final currentSong = context.select<MusicProvider, Song?>((p) => p.currentSong);
    final isPlaying = context.select<MusicProvider, bool>((p) => p.isPlaying);
    final canContinueListening = context.select<MusicProvider, bool>((p) => p.canContinueListening);
    final resumePositionMs = context.select<MusicProvider, int>((p) => p.resumePositionMs);
    final currentDuration = context.select<MusicProvider, Duration?>((p) => p.currentDuration);
    final intelligence = context.watch<IntelligenceProvider>();
    final modes = context.watch<ModeProvider>();
    final songs = library.allSongs;
    final children = <Widget>[
      const SizedBox(height: 6),
      AutopilotHomeCard(songCount: songs.length),
    ];

    if (canContinueListening && currentSong != null && !isPlaying) {
      final song = currentSong;
      final pos = resumePositionMs;
      final dur = (currentDuration ?? song.duration).inMilliseconds;
      final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
      children.addAll([
        const SizedBox(height: 14),
        ResonateGlassCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.history_rounded)),
            title: const Text('Continue listening', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${song.title}\n${_homeFormatClock(pos)} / ${_homeFormatClock(dur)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: FilledButton.tonalIcon(
              onPressed: () => music.continueListening(),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume'),
            ),
            onTap: () => music.continueListening(),
          ),
        ),
        if (progress > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: LinearProgressIndicator(value: progress, minHeight: 3),
          ),
      ]);
    }

    final history = context.watch<ListeningHistoryProvider>();
    final recentSongs = <Song>[];
    final seen = <String>{};
    for (final item in history.items) {
      final s = item.song;
      if (s == null || seen.contains(s.id)) continue;
      seen.add(s.id);
      recentSongs.add(s);
      if (recentSongs.length >= 12) break;
    }
    if (recentSongs.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Recently played', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recentSongs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final song = recentSongs[i];
              return SizedBox(
                width: 200,
                child: ResonateGlassCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    leading: const CircleAvatar(child: Icon(Icons.history_rounded, size: 18)),
                    title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      await music.playSong(song);
                      if (context.mounted) openShellPlayer(context);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ]);
    }

    if (intelligence.isEnabled) {
      children.addAll([
        const SizedBox(height: 16),
        const DrivingSuggestionBanner(),
        const ModeShelfCard(),
        const EvolvingMixCard(),
      ]);
    }

    if (currentSong != null) {
      children.addAll([
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Now playing', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        ResonateGlassCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: CircleAvatar(child: Icon(isPlaying ? Icons.graphic_eq : Icons.pause_rounded)),
            title: Text(currentSong.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(currentSong.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const DjModeStatusChip(dense: true),
            onTap: () => openShellPlayer(context),
          ),
        ),
      ]);
    }

    children.add(const SizedBox(height: 32));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }
}
