import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../services/audio_file_service.dart';
import '../widgets/audio_visualization_widget.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Now Playing'), actions: [Consumer<MusicProvider>(builder: (_, music, __) => IconButton(tooltip: 'Stop', icon: const Icon(Icons.stop_rounded), onPressed: music.currentSong == null ? null : music.stop))]),
    body: Consumer<MusicProvider>(builder: (context, music, _) {
      final song = music.currentSong;
      if (song == null) return const Center(child: Text('No song selected'));
      final duration = music.currentDuration ?? song.duration;
      final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
      final value = music.currentPosition.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
      return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
        Container(height: 250, decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), color: Theme.of(context).colorScheme.surfaceContainerHighest, border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)), child: Center(child: Icon(Icons.album_rounded, size: 110, color: Theme.of(context).colorScheme.primary))),
        const SizedBox(height: 20),
        Text(song.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6), Text(song.artist, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge), Text(song.album, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 18),
        ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(height: 105, padding: const EdgeInsets.all(8), color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const AudioVisualizationWidget())),
        const SizedBox(height: 12),
        Slider(value: value, min: 0, max: max, onChanged: (v) => music.seek(Duration(milliseconds: v.round()))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(AudioFileService.formatDuration(music.currentPosition)), Text(AudioFileService.formatDuration(duration))])),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(tooltip: 'Previous', iconSize: 34, onPressed: music.previousSong, icon: const Icon(Icons.skip_previous_rounded)),
          IconButton(tooltip: 'Back 10 seconds', iconSize: 28, onPressed: () => music.seek(Duration(milliseconds: (music.currentPosition.inMilliseconds - 10000).clamp(0, max.toInt()))), icon: const Icon(Icons.replay_10_rounded)),
          const SizedBox(width: 8),
          FloatingActionButton.large(heroTag: 'resonate-play', onPressed: music.togglePlayPause, child: Icon(music.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 40)),
          const SizedBox(width: 8),
          IconButton(tooltip: 'Forward 10 seconds', iconSize: 28, onPressed: () => music.seek(Duration(milliseconds: (music.currentPosition.inMilliseconds + 10000).clamp(0, max.toInt()))), icon: const Icon(Icons.forward_10_rounded)),
          IconButton(tooltip: 'Next', iconSize: 34, onPressed: music.nextSong, icon: const Icon(Icons.skip_next_rounded)),
        ]),
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), child: Row(children: [Icon(music.volume == 0 ? Icons.volume_off : Icons.volume_up, color: Theme.of(context).colorScheme.primary), Expanded(child: Slider(value: music.volume, min: 0, max: 1, onChanged: music.setVolume)), Text('${(music.volume * 100).round()}%', style: Theme.of(context).textTheme.labelLarge)]))),
      ]);
    }),
  );
}
