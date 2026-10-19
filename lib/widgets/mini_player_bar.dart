import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/music_provider.dart';

/// Lightweight, persistent playback controls shared by the main app surfaces.
/// It observes only the playback fields it renders, so position ticks rebuild
/// this small bar rather than the full navigation shell.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key, required this.onOpenPlayer});

  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final song = context.select<MusicProvider, Song?>((music) => music.currentSong);
    final isPlaying = context.select<MusicProvider, bool>((music) => music.isPlaying);
    final position = context.select<MusicProvider, Duration>((music) => music.currentPosition);
    final duration = context.select<MusicProvider, Duration?>((music) => music.currentDuration);

    if (song == null) return const SizedBox.shrink();

    final totalMs = (duration ?? song.duration).inMilliseconds;
    final progress = totalMs > 0
        ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onOpenPlayer,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors.primary, colors.tertiary],
                      ),
                    ),
                    child: const Icon(Icons.music_note_rounded, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: onOpenPlayer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isPlaying ? 'Pause' : 'Play',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => context.read<MusicProvider>().togglePlayPause(
                        source: 'mini_player',
                      ),
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
