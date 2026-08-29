import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/library_provider.dart';
import '../services/audio_service.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    context.read<LibraryProvider>().searchSongs(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resonate'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final libraryProvider = context.read<LibraryProvider>();
              await libraryProvider.loadAllSongs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Library refreshed')),
              );
            },
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('Sort by Title'),
                onTap: () => context.read<LibraryProvider>().setSortBy('title'),
              ),
              PopupMenuItem(
                child: const Text('Sort by Artist'),
                onTap: () => context.read<LibraryProvider>().setSortBy('artist'),
              ),
              PopupMenuItem(
                child: const Text('Sort by Album'),
                onTap: () => context.read<LibraryProvider>().setSortBy('album'),
              ),
              PopupMenuItem(
                child: const Text('Sort by Date Added'),
                onTap: () => context.read<LibraryProvider>().setSortBy('date_added'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                child: const Text('Filter: All'),
                onTap: () => context.read<LibraryProvider>().setFilterBy('all'),
              ),
              PopupMenuItem(
                child: const Text('Filter: Favorites'),
                onTap: () => context.read<LibraryProvider>().setFilterBy('favorites'),
              ),
              PopupMenuItem(
                child: const Text('Filter: Recent'),
                onTap: () => context.read<LibraryProvider>().setFilterBy('recent'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          // Statistics bar
          Consumer<LibraryProvider>(
            builder: (context, libraryProvider, _) {
              final stats = libraryProvider.statistics;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          '${stats['totalSongs'] ?? 0}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Songs',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '${stats['favoriteCount'] ?? 0}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Favorites',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '${stats['totalPlaylists'] ?? 0}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Playlists',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          // Songs list
          Expanded(
            child: Consumer<LibraryProvider>(
              builder: (context, libraryProvider, _) {
                final songs = libraryProvider.allSongs;

                if (songs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No songs found',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          libraryProvider.searchQuery.isNotEmpty
                              ? 'Try a different search'
                              : 'Add songs to get started',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return ListTile(
                      leading: Icon(
                        Icons.music_note,
                        color: context.read<MusicProvider>().currentSong?.id ==
                                song.id
                            ? Theme.of(context).primaryColor
                            : null,
                      ),
                      title: Text(song.title),
                      subtitle: Text(song.artist),
                      trailing: PopupMenuButton(
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            child: const Text('Add to favorites'),
                            onTap: () {
                              libraryProvider.addFavorite(song);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Added to favorites'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                          PopupMenuItem(
                            child: const Text('Delete'),
                            onTap: () {
                              libraryProvider.deleteSong(song.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Song deleted'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      selected:
                          context.read<MusicProvider>().currentSong?.id ==
                              song.id,
                      onTap: () async {
                        final musicProvider = context.read<MusicProvider>();
                        await musicProvider.playSong(song);
                        await libraryProvider.updatePlayCount(song.id);
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PlayerScreen(),
                            ),
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
