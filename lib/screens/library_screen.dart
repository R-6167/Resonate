import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import '../providers/library_provider.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    Key? key,
  }) : super(key: key);

  @override
  State<LibraryScreen> createState() =>
      _LibraryScreenState();
}

class _LibraryScreenState
    extends State<LibraryScreen> {
  final TextEditingController _searchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();

    _searchController.addListener(
      _onSearchChanged,
    );
  }

  void _onSearchChanged() {
    context
        .read<LibraryProvider>()
        .searchSongs(
          _searchController.text,
        );

    setState(() {});
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
              final libraryProvider =
                  context.read<LibraryProvider>();

              await libraryProvider.loadAllSongs();

              if (!mounted) {
                return;
              }

              ScaffoldMessenger.of(context)
                  .showSnackBar(
                const SnackBar(
                  content:
                      Text('Library refreshed'),
                ),
              );
            },
          ),

          // Explicit generic type fixes the PopupMenu
          // type inference error.
          PopupMenuButton<String>(
            onSelected: (value) {
              final libraryProvider =
                  context.read<LibraryProvider>();

              switch (value) {
                case 'title':
                  libraryProvider.setSortBy(
                    'title',
                  );
                  break;

                case 'artist':
                  libraryProvider.setSortBy(
                    'artist',
                  );
                  break;

                case 'album':
                  libraryProvider.setSortBy(
                    'album',
                  );
                  break;

                case 'date_added':
                  libraryProvider.setSortBy(
                    'date_added',
                  );
                  break;

                case 'all':
                  libraryProvider.setFilterBy(
                    'all',
                  );
                  break;

                case 'favorites':
                  libraryProvider.setFilterBy(
                    'favorites',
                  );
                  break;

                case 'recent':
                  libraryProvider.setFilterBy(
                    'recent',
                  );
                  break;
              }
            },
            itemBuilder: (context) =>
                const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'title',
                child: Text('Sort by Title'),
              ),
              PopupMenuItem<String>(
                value: 'artist',
                child: Text('Sort by Artist'),
              ),
              PopupMenuItem<String>(
                value: 'album',
                child: Text('Sort by Album'),
              ),
              PopupMenuItem<String>(
                value: 'date_added',
                child: Text('Sort by Date Added'),
              ),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'all',
                child: Text('Filter: All'),
              ),
              PopupMenuItem<String>(
                value: 'favorites',
                child: Text('Filter: Favorites'),
              ),
              PopupMenuItem<String>(
                value: 'recent',
                child: Text('Filter: Recent'),
              ),
            ],
          ),
        ],
      ),

      body: Column(
        children: [
          // -------------------------------------------------------------------
          // SEARCH
          // -------------------------------------------------------------------

          Padding(
            padding:
                const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText:
                    'Search songs, artists, albums...',
                prefixIcon:
                    const Icon(Icons.search),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                            ),
                            onPressed: () {
                              _searchController
                                  .clear();
                            },
                          )
                        : null,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // STATISTICS
          // -------------------------------------------------------------------

          Consumer<LibraryProvider>(
            builder:
                (context, libraryProvider, _) {
              final stats =
                  libraryProvider.statistics;

              return Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 16.0,
                ),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      value:
                          '${stats['totalSongs'] ?? 0}',
                      label: 'Songs',
                    ),
                    _StatItem(
                      value:
                          '${stats['favoriteCount'] ?? 0}',
                      label: 'Favorites',
                    ),
                    _StatItem(
                      value:
                          '${stats['totalPlaylists'] ?? 0}',
                      label: 'Playlists',
                    ),
                  ],
                ),
              );
            },
          ),

          const Divider(),

          // -------------------------------------------------------------------
          // SONG LIST
          // -------------------------------------------------------------------

          Expanded(
            child:
                Consumer<LibraryProvider>(
              builder:
                  (context, libraryProvider, _) {
                final songs =
                    libraryProvider.allSongs;

                if (songs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        Text(
                          'No songs found',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge,
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        Text(
                          libraryProvider
                                  .searchQuery
                                  .isNotEmpty
                              ? 'Try a different search'
                              : 'Add songs to get started',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: songs.length,
                  itemBuilder:
                      (context, index) {
                    final song = songs[index];

                    final musicProvider =
                        context
                            .read<MusicProvider>();

                    final isCurrent =
                        musicProvider.currentSong
                                ?.id ==
                            song.id;

                    return ListTile(
                      leading: Icon(
                        Icons.music_note,
                        color: isCurrent
                            ? Theme.of(context)
                                .primaryColor
                            : null,
                      ),
                      title: Text(
                        song.title,
                      ),
                      subtitle: Text(
                        song.artist,
                      ),
                      trailing:
                          PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value ==
                              'favorite') {
                            await libraryProvider
                                .addFavorite(song);

                            if (!mounted) {
                              return;
                            }

                            ScaffoldMessenger
                                    .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Added to favorites',
                                ),
                                duration:
                                    Duration(
                                  seconds: 1,
                                ),
                              ),
                            );
                          }

                          if (value ==
                              'delete') {
                            await libraryProvider
                                .deleteSong(
                              song.id,
                            );

                            if (!mounted) {
                              return;
                            }

                            ScaffoldMessenger
                                    .of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Song deleted',
                                ),
                                duration:
                                    Duration(
                                  seconds: 1,
                                ),
                              ),
                            );
                          }
                        },
                        itemBuilder:
                            (context) =>
                                const <
                                    PopupMenuEntry<
                                        String>>[
                          PopupMenuItem<String>(
                            value: 'favorite',
                            child: Text(
                              'Add to favorites',
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text(
                              'Delete',
                            ),
                          ),
                        ],
                      ),
                      selected: isCurrent,
                      onTap: () async {
                        final musicProvider =
                            context.read<
                                MusicProvider>();

                        await musicProvider
                            .playSong(song);

                        await libraryProvider
                            .updatePlayCount(
                          song.id,
                        );

                        if (!mounted) {
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const PlayerScreen(),
                          ),
                        );
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
    _searchController.removeListener(
      _onSearchChanged,
    );

    _searchController.dispose();

    super.dispose();
  }
}

// -----------------------------------------------------------------------------
// STATISTICS WIDGET
// -----------------------------------------------------------------------------

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium,
        ),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall,
        ),
      ],
    );
  }
}
