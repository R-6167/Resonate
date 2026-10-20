import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../ui/resonate_glass.dart';
import 'player_screen.dart';
import '../navigation/shell_nav.dart';

class AlbumScreen extends StatelessWidget {
  final String album;
  final String? artistHint;

  const AlbumScreen({super.key, required this.album, this.artistHint});

  @override
  Widget build(BuildContext context) {
    return Consumer2<LibraryProvider, MusicProvider>(
      builder: (context, library, music, _) {
        final songs = library.allSongs
            .where((s) => s.album == album)
            .toList()
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

        final artist = artistHint ??
            (songs.isNotEmpty ? songs.first.artist : 'Unknown Artist');

        return ResonateGlassScaffold(
          title: Text(album),
          body: songs.isEmpty
              ? const Center(child: Text('No tracks in this album.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              artist,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            '${songs.length} track${songs.length == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              await music.setShuffleEnabled(false);
                              await music.playSong(
                                songs.first,
                                queue: List<Song>.from(songs),
                                startIndex: 0,
                              );
                              if (context.mounted) {
                                openShellPlayer(context);
                              }
                            },
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play'),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            tooltip: 'Shuffle album',
                            onPressed: () async {
                              final shuffled = List<Song>.from(songs)..shuffle();
                              await music.setShuffleEnabled(true);
                              await music.playSong(
                                shuffled.first,
                                queue: shuffled,
                                startIndex: 0,
                              );
                              if (context.mounted) {
                                openShellPlayer(context);
                              }
                            },
                            icon: const Icon(Icons.shuffle_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: songs.length,
                        itemBuilder: (_, i) {
                          final song = songs[i];
                          final current = music.currentSong?.id == song.id;
                          return ListTile(
                            selected: current,
                            leading: Text('${i + 1}'),
                            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Text(_fmt(song.duration)),
                            onTap: () async {
                              await music.playSong(
                                song,
                                queue: List<Song>.from(songs),
                                startIndex: i,
                              );
                              if (context.mounted) {
                                openShellPlayer(context);
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
