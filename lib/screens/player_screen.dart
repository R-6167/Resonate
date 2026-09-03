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
                    children: [
                      Expanded(
                        child: _PlayerControl(
                          tooltip: 'Previous song',
                          icon: Icons.skip_previous_rounded,
                          onPressed: music.previousSong,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _PlayerControl(
                          tooltip: 'Back 10 seconds',
                          icon: Icons.replay_10_rounded,
                          onPressed: () => music.seek(
                            Duration(
                              milliseconds: (music.currentPosition.inMilliseconds - 10000)
                                  .clamp(0, max.toInt()),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PlayPauseControl(
                        isPlaying: music.isPlaying,
                        onPressed: music.togglePlayPause,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _PlayerControl(
                          tooltip: 'Forward 10 seconds',
                          icon: Icons.forward_10_rounded,
                          onPressed: () => music.seek(
                            Duration(
                              milliseconds: (music.currentPosition.inMilliseconds + 10000)
                                  .clamp(0, max.toInt()),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _PlayerControl(
                          tooltip: 'Next song',
                          icon: Icons.skip_next_rounded,
                          onPressed: music.nextSong,
                        ),
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

class _PlayerControl extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _PlayerControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 58,
        child: Material(
          color: scheme.primaryContainer,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onPressed,
            child: Center(
              child: Icon(
                icon,
                size: 30,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseControl extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const _PlayPauseControl({
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: isPlaying ? 'Pause' : 'Play',
      child: Material(
        color: scheme.primary,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 68,
            height: 68,
            child: Center(
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 42,
                color: scheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
