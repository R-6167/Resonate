import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/audio_visualization_provider.dart';
import '../services/audio_service.dart';
import '../widgets/audio_visualization_widget.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        elevation: 0,
      ),
      body: Consumer<MusicProvider>(
        builder: (context, musicProvider, _) {
          final song = musicProvider.currentSong;

          if (song == null) {
            return const Center(
              child: Text('No song selected'),
            );
          }

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Audio Visualization
                  const AudioVisualizationWidget(),
                  const SizedBox(height: 32),

                  // Album Art Placeholder
                  Container(
                    height: 250,
                    width: 250,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.music_note,
                        size: 80,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Song Info
                  Text(
                    song.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    song.artist,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Progress Bar
                  StreamBuilder<Duration?>(
                    stream: musicProvider.audioPlayer.durationStream,
                    builder: (context, snapshot) {
                      final duration = snapshot.data ?? Duration.zero;
                      return Column(
                        children: [
                          Slider(
                            value: musicProvider.currentPosition.inSeconds
                                .toDouble(),
                            max: duration.inSeconds.toDouble(),
                            onChanged: (value) {
                              musicProvider.seek(
                                Duration(seconds: value.toInt()),
                              );
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  AudioFileService.formatDuration(
                                    musicProvider.currentPosition,
                                  ),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  AudioFileService.formatDuration(duration),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 32),

                  // Playback Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        iconSize: 32,
                        onPressed: () => musicProvider.previousSong(),
                      ),
                      const SizedBox(width: 16),
                      FloatingActionButton(
                        onPressed: () => musicProvider.togglePlayPause(),
                        child: Icon(
                          musicProvider.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        iconSize: 32,
                        onPressed: () => musicProvider.nextSong(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Volume Control
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Volume',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: 0.5,
                          min: 0,
                          max: 1,
                          onChanged: (value) =>
                              musicProvider.setVolume(value),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}