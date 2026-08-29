import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/music_provider.dart';
import '../providers/library_provider.dart';
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final library = Provider.of<LibraryProvider>(context);
    final music = Provider.of<MusicProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resonate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final q = await showSearch<String?>(
                context: context,
                delegate: _SongSearchDelegate(library),
              );
              if (q != null) library.searchSongs(q);
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              // Placeholder: future settings screen
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings coming soon')));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => library.loadAllSongs(),
              child: library.allSongs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.music_note, size: 72, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text('No songs found', style: TextStyle(fontSize: 18)),
                            const SizedBox(height: 8),
                            const Text('Tap the scan button to search your device for audio files.'),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Scan Storage'),
                              onPressed: () async {
                                final home = Directory('/storage/emulated/0/');
                                if (await home.exists()) {
                                  await library.scanDirectory(home);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan complete')));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No accessible storage root')));
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: library.allSongs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = library.allSongs[i];
                        final isCurrent = music.currentSong?.id == s.id;
                        return ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isCurrent ? Colors.indigo.shade100 : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.music_note, color: Colors.black54),
                          ),
                          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${s.artist} • ${s.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(isCurrent && music.isPlaying ? Icons.pause : Icons.play_arrow),
                                onPressed: () async {
                                  if (isCurrent) {
                                    await music.playPause();
                                  } else {
                                    await music.playSong(s);
                                  }
                                  await library.updatePlayCount(s.id);
                                },
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'fav') {
                                    final fav = await library.isFavorite(s.id);
                                    if (fav) {
                                      await library.removeFavorite(s.id);
                                    } else {
                                      await library.addFavorite(s);
                                    }
                                  } else if (v == 'delete') {
                                    await library.deleteSong(s.id);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(value: 'fav', child: Text('Toggle Favorite')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete from library')),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          _PlaybackBar(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.folder_open),
        onPressed: () async {
          final home = Directory('/storage/emulated/0/');
          if (await home.exists()) {
            await library.scanDirectory(home);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan complete')));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No accessible storage root')));
          }
        },
      ),
    );
  }
}

class _PlaybackBar extends StatefulWidget {
  @override
  State<_PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends State<_PlaybackBar> {
  Duration _position = Duration.zero;

  @override
  Widget build(BuildContext context) {
    final music = Provider.of<MusicProvider>(context);
    final song = music.currentSong;

    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song != null)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(song.artist, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(music.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36),
                  onPressed: () => music.playPause(),
                ),
              ],
            ),
          if (song != null) StreamBuilder<Duration>(
            stream: music.positionStream,
            builder: (context, snapPos) {
              final pos = snapPos.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: music.durationStream,
                builder: (context, snapDur) {
                  final dur = snapDur.data ?? Duration.zero;
                  return Column(
                    children: [
                      Slider(
                        value: dur.inMilliseconds > 0 ? pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble() : 0.0,
                        max: dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0,
                        onChanged: (v) {
                          music.seek(Duration(milliseconds: v.toInt()));
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(pos), style: const TextStyle(fontSize: 12)),
                          Text(_formatDuration(dur), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text('Crossfade'),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: 10,
                              divisions: 10,
                              value: 3,
                              onChanged: (v) async {
                                await music.setCrossfade(Duration(seconds: v.toInt()));
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          if (song == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Row(
                children: const [
                  Icon(Icons.music_note),
                  SizedBox(width: 8),
                  Text('No song playing'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$mm:$ss';
  }
}

class _SongSearchDelegate extends SearchDelegate<String?> {
  final LibraryProvider library;
  _SongSearchDelegate(this.library);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  }

  @override
  Widget buildResults(BuildContext context) {
    library.searchSongs(query);
    return Center(child: Text('Searching for "$query"'));
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = library.allSongs.where((s) => s.title.toLowerCase().contains(query.toLowerCase())).toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final s = results[i];
        return ListTile(
          title: Text(s.title),
          onTap: () => close(context, query),
        );
      },
    );
  }
}
