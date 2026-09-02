import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../services/audio_file_service.dart';
import '../widgets/audio_visualization_widget.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Now Playing'),
          actions: [
            Consumer<MusicProvider>(
              builder: (_, music, __) => IconButton(
                tooltip: 'Stop',
                icon: const Icon(Icons.stop_rounded),
                onPressed: music.currentSong == null ? null : music.stop,
              ),
            ),
          ],
        ),
        body: Consumer<MusicProvider>(
          builder: (context, music, _) {
            final song = music.currentSong;
            if (song == null) return const Center(child: Text('No song selected'));
            final duration = music.currentDuration ?? song.duration;
            final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
            final value = music.currentPosition.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
            final scheme = Theme.of(context).colorScheme;

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                Container(
                  height: 250,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    color: scheme.surfaceContainerHighest,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Center(
                    child: Icon(Icons.album_rounded, size: 110, color: scheme.primary),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  song.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(song.artist, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                Text(song.album, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 105,
                    padding: const EdgeInsets.all(8),
                    color: scheme.surfaceContainerHighest,
                    child: const AudioVisualizationWidget(),
                  ),
                ),
                const SizedBox(height: 12),
                Slider(
                  value: value,
                  min: 0,
                  max: max,
                  onChanged: (v) => music.seek(Duration(milliseconds: v.round())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AudioFileService.formatDuration(music.currentPosition)),
                      Text(AudioFileService.formatDuration(duration)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: scheme.surfaceContainerHighest,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ControlButton(
                        tooltip: 'Previous song',
                        icon: Icons.skip_previous_rounded,
                        onPressed: music.previousSong,
                      ),
                      _ControlButton(
                        tooltip: 'Back 10 seconds',
                        icon: Icons.replay_10_rounded,
                        onPressed: () => music.seek(
                          Duration(milliseconds: (music.currentPosition.inMilliseconds - 10000).clamp(0, max.toInt())),
                        ),
                      ),
                      FloatingActionButton.large(
                        heroTag: 'resonate-play',
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        tooltip: music.isPlaying ? 'Pause' : 'Play',
                        onPressed: music.togglePlayPause,
                        child: Icon(
                          music.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 42,
                        ),
                      ),
                      _ControlButton(
                        tooltip: 'Forward 10 seconds',
                        icon: Icons.forward_10_rounded,
                        onPressed: () => music.seek(
                          Duration(milliseconds: (music.currentPosition.inMilliseconds + 10000).clamp(0, max.toInt())),
                        ),
                      ),
                      _ControlButton(
                        tooltip: 'Next song',
                        icon: Icons.skip_next_rounded,
                        onPressed: music.nextSong,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          music.volume == 0 ? Icons.volume_off : Icons.volume_up,
                          color: scheme.primary,
                        ),
                        Expanded(
                          child: Slider(
                            value: music.volume,
                            min: 0,
                            max: 1,
                            onChanged: music.setVolume,
                          ),
                        ),
                        Text('${(music.volume * 100).round()}%', style: Theme.of(context).textTheme.labelLarge),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _ControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _ControlButton({required this.tooltip, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 30,
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(minWidth: 58, minHeight: 58),
        color: scheme.onPrimaryContainer,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
