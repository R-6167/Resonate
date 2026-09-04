import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import 'player_screen.dart';

class LikedSongsScreen extends StatelessWidget {
  const LikedSongsScreen({super.key});

  Future<void> _play(BuildContext context, List<Song> songs, int index) async {
    final ok = await context.read<MusicProvider>().playSong(songs[index], queue: songs, startIndex: index);
    if (ok && context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  Future<void> _addAll(BuildContext context, List<Song> songs) async {
    var added = 0;
    final music = context.read<MusicProvider>();
    for (final song in songs) {
      final result = await music.addToQueue(song);
      if (result) added++;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added == 0 ? 'Liked songs are already in the queue.' : 'Added $added liked songs to the queue.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liked Songs'),
        actions: [
          Consumer<LibraryProvider>(
            builder: (_, library, __) => IconButton(
              tooltip: 'Add all to queue',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: library.favoriteSongs.isEmpty ? null : () => _addAll(context, library.favoriteSongs),
            ),
          ),
        ],
      ),
      body: Consumer<LibraryProvider>(
        builder: (context, library, _) {
          final songs = library.favoriteSongs;
          if (songs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.favorite_border_rounded, size: 64),
                  SizedBox(height: 16),
                  Text('No liked songs yet'),
                  SizedBox(height: 8),
                  Text('Tap the heart on a song to build your personal collection.', textAlign: TextAlign.center),
                ]),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(children: [
                  Expanded(child: Text('${songs.length} liked songs', style: Theme.of(context).textTheme.titleMedium)),
                  FilledButton.icon(onPressed: () => _play(context, songs, 0), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play all')),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (_, index) {
                    final song = songs[index];
                    return ListTile(
                      leading: const Icon(Icons.favorite_rounded),
                      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(icon: const Icon(Icons.favorite_rounded), tooltip: 'Unlike', onPressed: () => library.removeFavorite(song.id)),
                      onTap: () => _play(context, songs, index),
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
