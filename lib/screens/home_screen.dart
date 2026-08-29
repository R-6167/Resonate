import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/music_provider.dart';
import '../providers/library_provider.dart';
import 'dart:io';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

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
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => library.loadAllSongs(),
              child: ListView.builder(
                itemCount: library.allSongs.length,
                itemBuilder: (context, i) {
                  final s = library.allSongs[i];
                  final isCurrent = music.currentSong?.id == s.id;
                  return ListTile(
                    leading: Icon(isCurrent && music.isPlaying ? Icons.pause_circle_filled : Icons.music_note),
                    title: Text(s.title),
                    subtitle: Text('${s.artist} • ${s.album}'),
                    trailing: IconButton(
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
          // Try scanning common directories
          // NOTE: Users should run `flutter create .` if platform folders are missing.
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

class _PlaybackBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final music = Provider.of<MusicProvider>(context);
    final song = music.currentSong;
    return Container(
      color: Theme.of(context).cardColor,
      child: ListTile(
        leading: const Icon(Icons.music_note),
        title: Text(song?.title ?? 'No song playing'),
        subtitle: Text(song?.artist ?? ''),
        trailing: IconButton(
          icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () => music.playPause(),
        ),
      ),
    );
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
