import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../ui/resonate_glass.dart';
import 'player_screen.dart';

class LikedSongsScreen extends StatelessWidget {
  const LikedSongsScreen({super.key});

  String _formatDuration(Duration d) {
    if (d.inMilliseconds <= 0) return '—';
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _play(BuildContext context, List<Song> songs, int index) async {
    final music = context.read<MusicProvider>();
    await music.setShuffleEnabled(false);
    final ok = await music.playSong(
      songs[index],
      queue: List<Song>.from(songs),
      startIndex: index,
    );
    if (ok && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayerScreen()),
      );
    }
  }

  Future<void> _shuffle(BuildContext context, List<Song> songs) async {
    if (songs.isEmpty) return;
    final shuffled = List<Song>.from(songs)..shuffle();
    final music = context.read<MusicProvider>();
    await music.setShuffleEnabled(true);
    final ok = await music.playSong(
      shuffled.first,
      queue: shuffled,
      startIndex: 0,
    );
    if (ok && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayerScreen()),
      );
    }
  }

  Future<void> _addAll(BuildContext context, List<Song> songs) async {
    var added = 0;
    final music = context.read<MusicProvider>();
    for (final song in songs) {
      if (await music.addToQueue(song)) added++;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? 'Liked songs are already in the queue.'
              : 'Added $added liked songs to the queue.',
        ),
      ),
    );
  }

  Future<void> _playNext(BuildContext context, Song song) async {
    await HapticFeedback.mediumImpact();
    final ok = await context.read<MusicProvider>().playNext(song);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Playing next: ${song.title}' : 'Could not queue next',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResonateGlassScaffold(
      title: const Text('Liked Songs'),
      actions: [
        Consumer<LibraryProvider>(
          builder: (_, library, __) => IconButton(
            tooltip: 'Add all to queue',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: library.favoriteSongs.isEmpty
                ? null
                : () => _addAll(context, library.favoriteSongs),
          ),
        ),
      ],
      body: Consumer<LibraryProvider>(
        builder: (context, library, _) {
          final songs = library.favoriteSongs;
          if (songs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border_rounded, size: 64),
                    SizedBox(height: 16),
                    Text('No liked songs yet'),
                    SizedBox(height: 8),
                    Text(
                      'Tap the heart on a song to build your personal collection.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${songs.length} liked',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _play(context, songs, 0),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _shuffle(context, songs),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (_, index) {
                    final song = songs[index];
                    return ListTile(
                      leading: const Icon(Icons.favorite_rounded),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatDuration(song.duration),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          IconButton(
                            icon: const Icon(Icons.favorite_rounded),
                            tooltip: 'Unlike',
                            onPressed: () => library.removeFavorite(song.id),
                          ),
                        ],
                      ),
                      onTap: () => _play(context, songs, index),
                      onLongPress: () => _playNext(context, song),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
