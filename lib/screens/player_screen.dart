import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../services/audio_file_service.dart';
import '../widgets/audio_visualization_widget.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<MusicProvider>(
        builder: (context, music, _) {
          final song = music.currentSong;
          if (song == null) {
            return const Center(child: Text('No song selected'));
          }

          final duration = music.currentDuration ?? song.duration;
          final maxSeconds = duration.inSeconds.toDouble();
          final position = music.currentPosition.inSeconds
              .clamp(0, duration.inSeconds)
              .toDouble();

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).colorScheme.primaryContainer,
                          Theme.of(context).colorScheme.surface,
                        ],
                      ),
                    ),
                    child: Center(
                      child: Container(
                        height: 220,
                        width: 220,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(.1),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.music_note,
                          size: 100,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Theme.of(context).colorScheme.primaryContainer,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: AudioVisualizationWidget(),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          song.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(song.artist, style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 4),
                        Text(song.album, style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 24),
                        Slider(
                          value: position,
                          max: maxSeconds > 0 ? maxSeconds : 1,
                          onChanged: maxSeconds <= 0
                              ? null
                              : (value) => music.seek(Duration(seconds: value.round())),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(AudioFileService.formatDuration(music.currentPosition)),
                              Text(AudioFileService.formatDuration(duration)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.outlined(
                              icon: const Icon(Icons.skip_previous),
                              iconSize: 30,
                              onPressed: music.previousSong,
                            ),
                            const SizedBox(width: 24),
                            FloatingActionButton(
                              heroTag: 'play-btn',
                              onPressed: music.togglePlayPause,
                              child: Icon(
                                music.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 34,
                              ),
                            ),
                            const SizedBox(width: 24),
                            IconButton.outlined(
                              icon: const Icon(Icons.skip_next),
                              iconSize: 30,
                              onPressed: music.nextSong,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.volume_up,
                                    color: Theme.of(context).colorScheme.primary),
                                Expanded(
                                  child: Slider(
                                    value: .5,
                                    min: 0,
                                    max: 1,
                                    onChanged: music.setVolume,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
