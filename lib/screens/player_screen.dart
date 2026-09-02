import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/audio_visualization_provider.dart';
import '../services/audio_file_service.dart';
import '../widgets/audio_visualization_widget.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<MusicProvider>(
        builder: (context, musicProvider, _) {
          final song = musicProvider.currentSong;

          if (song == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_note,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No song selected',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select a song from your library to start playing',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              // Custom AppBar with album art
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
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Center(
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
              ),

              // Main content
              SliverList(
                delegate: SliverChildListDelegate(
                  [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Audio Visualization
                          Container(
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: AudioVisualizationWidget(),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Song Info
                          Text(
                            song.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
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
                          const SizedBox(height: 4),
                          Text(
                            song.album,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // Progress Bar
                          StreamBuilder<Duration?>(
                            stream:
                                musicProvider.audioPlayer.durationStream,
                            builder: (context, snapshot) {
                              final duration =
                                  snapshot.data ?? Duration.zero;
                              return Column(
                                children: [
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 6,
                                      thumbShape:
                                          const RoundSliderThumbShape(
                                        enabledThumbRadius: 8,
                                      ),
                                    ),
                                    child: Slider(
                                      value: musicProvider
                                          .currentPosition
                                          .inSeconds
                                          .toDouble(),
                                      max: duration.inSeconds.toDouble(),
                                      onChanged: (value) {
                                        musicProvider.seek(
                                          Duration(
                                            seconds: value.toInt(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets
                                        .symmetric(horizontal: 16),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment
                                              .spaceBetween,
                                      children: [
                                        Text(
                                          AudioFileService
                                              .formatDuration(
                                            musicProvider
                                                .currentPosition,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        Text(
                                          AudioFileService
                                              .formatDuration(
                                            duration,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
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
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              IconButton.outlined(
                                icon: const Icon(
                                    Icons.skip_previous),
                                iconSize: 28,
                                onPressed: () =>
                                    musicProvider.previousSong(),
                              ),
                              const SizedBox(width: 24),
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withOpacity(0.7),
                                    ],
                                  ),
                                ),
                                child: FloatingActionButton(
                                  heroTag: 'play-btn',
                                  backgroundColor:
                                      Colors.transparent,
                                  elevation: 0,
                                  onPressed: () =>
                                      musicProvider
                                          .togglePlayPause(),
                                  child: Icon(
                                    musicProvider.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 32,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              IconButton.outlined(
                                icon: const Icon(Icons.skip_next),
                                iconSize: 28,
                                onPressed: () =>
                                    musicProvider.nextSong(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // Volume Control
                          Card(
                            child: Padding(
                              padding:
                                  const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.volume_up,
                                        size: 20,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Volume',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Slider(
                                    value: 0.5,
                                    min: 0,
                                    max: 1,
                                    onChanged: (value) =>
                                        musicProvider
                                            .setVolume(value),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
