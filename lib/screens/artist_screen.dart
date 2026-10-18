import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../ui/resonate_glass.dart';
import 'album_screen.dart';
import 'player_screen.dart';

class ArtistScreen extends StatelessWidget {
  final String artist;

  const ArtistScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    return Consumer2<LibraryProvider, MusicProvider>(
      builder: (context, library, music, _) {
        final songs = library.allSongs
            .where((s) => s.artist == artist)
            .toList()
          ..sort((a, b) {
            final c = a.album.toLowerCase().compareTo(b.album.toLowerCase());
            if (c != 0) return c;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });

        final albums = <String>{};
        for (final s in songs) {
          albums.add(s.album);
        }

        return ResonateGlassScaffold(
          title: Text(artist),
          body: songs.isEmpty
              ? const Center(child: Text('No tracks for this artist.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${albums.length} album${albums.length == 1 ? '' : 's'} · ${songs.length} tracks',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              await music.setShuffleEnabled(false);
                              await music.playSong(
                                songs.first,
                                queue: List<Song>.from(songs),
                                startIndex: 0,
                              );
                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PlayerScreen(),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play'),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            tooltip: 'Shuffle artist',
                            onPressed: () async {
                              final shuffled = List<Song>.from(songs)..shuffle();
                              await music.setShuffleEnabled(true);
                              await music.playSong(
                                shuffled.first,
                                queue: shuffled,
                                startIndex: 0,
                              );
                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PlayerScreen(),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.shuffle_rounded),
                          ),
                        ],
                      ),
                    ),
                    if (albums.length > 1) ...[
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final album in albums)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: Text(album),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AlbumScreen(
                                          album: album,
                                          artistHint: artist,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    Expanded(
                      child: ListView.builder(
                        itemCount: songs.length,
                        itemBuilder: (_, i) {
                          final song = songs[i];
                          final current = music.currentSong?.id == song.id;
                          return ListTile(
                            selected: current,
                            leading: const Icon(Icons.music_note_rounded),
                            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(song.album, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Text(_fmt(song.duration)),
                            onTap: () async {
                              await music.playSong(
                                song,
                                queue: List<Song>.from(songs),
                                startIndex: i,
                              );
                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PlayerScreen(),
                                  ),
                                );
                              }
                            },
                            onLongPress: () async {
                              await HapticFeedback.mediumImpact();
                              final ok = await music.playNext(song);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Playing next: ${song.title}'
                                        : 'Could not queue next',
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  static String _fmt(Duration d) {
    if (d.inMilliseconds <= 0) return '—';
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
