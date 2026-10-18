import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/song.dart';
import '../ui/resonate_glass.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/audio_file_service.dart';
import 'liked_songs_screen.dart';
import 'library_management_screen.dart';
import 'player_screen.dart';
import 'playlists_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';

String _formatDuration(Duration d) {
  if (d.inMilliseconds <= 0) return '—';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

Duration _totalDuration(List<Song> songs) {
  var total = Duration.zero;
  for (final s in songs) {
    total += s.duration;
  }
  return total;
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();
  bool _hasSelectedFolders = false;
  bool _selectMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _refreshFolderVisibility();
  }

  Future<void> _refreshFolderVisibility() async {
    final folders = await AudioFileService.getSelectedFolders();
    if (mounted) {
      setState(() => _hasSelectedFolders = folders.isNotEmpty);
    }
  }

  void _onSearchChanged() {
    context.read<LibraryProvider>().searchSongs(_searchController.text);
    setState(() {});
  }

  void _toggleSelectMode([bool? on]) {
    setState(() {
      _selectMode = on ?? !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }


  Future<void> _batchPlayNext(List<Song> songs) async {
    final music = context.read<MusicProvider>();
    final picked = songs.where((s) => _selectedIds.contains(s.id)).toList();
    var added = 0;
    for (final s in picked.reversed) {
      if (await music.playNext(s)) added++;
    }
    if (!mounted) return;
    _toggleSelectMode(false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Queued $added track${added == 1 ? '' : 's'} to play next')),
    );
  }

  Future<void> _batchAddToQueue(List<Song> songs) async {
    final music = context.read<MusicProvider>();
    final picked = songs.where((s) => _selectedIds.contains(s.id)).toList();
    var added = 0;
    for (final s in picked) {
      if (await music.addToQueue(s)) added++;
    }
    if (!mounted) return;
    _toggleSelectMode(false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added $added track${added == 1 ? '' : 's'} to queue')),
    );
  }

  Future<void> _batchAddToPlaylist(List<Song> songs) async {
    final picked = songs.where((s) => _selectedIds.contains(s.id)).toList();
    if (picked.isEmpty) return;
    final provider = context.read<PlaylistProvider>();
    if (provider.playlists.isEmpty) await provider.loadPlaylists();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Playlist>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Add selection to playlist')),
            ...provider.playlists.map(
              (p) => ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(p.name),
                onTap: () => Navigator.pop(sheetContext, p),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await provider.addSongs(selected.id, picked);
    if (!mounted) return;
    _toggleSelectMode(false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${picked.length} tracks to ${selected.name}')),
    );
  }

  Future<void> _playSong(List<Song> songs, int index) async {
    final music = context.read<MusicProvider>();
    final library = context.read<LibraryProvider>();
    final song = songs[index];
    final fromHere = songs.sublist(index);
    final resumeAt = music.resumePositionFor(song.id);
    final playback = music.playSong(
      song,
      queue: List<Song>.from(fromHere),
      startIndex: 0,
      resumeIfPossible: resumeAt != null,
      resumeAtMs: resumeAt,
    );
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayerScreen()),
      );
    }
    final ok = await playback;
    if (!mounted) return;
    if (ok) {
      await library.updatePlayCount(song.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to play this song. Check that the file is still available.',
          ),
        ),
      );
    }
  }

  Future<void> _addToQueueWithHaptic(Song song) async {
    final music = context.read<MusicProvider>();
    await HapticFeedback.mediumImpact();
    final added = await music.addToQueue(song);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Added to queue: ${song.title}' : 'Already in the queue',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addToPlaylist(Song song) async {
    final provider = context.read<PlaylistProvider>();
    if (provider.playlists.isEmpty) {
      await provider.loadPlaylists();
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<Playlist>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Add to playlist'),
              subtitle: Text('Choose where to save this song.'),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('Create new playlist'),
              onTap: () async {
                final name = TextEditingController();
                final description = TextEditingController();
                final result = await showDialog<List<String>>(
                  context: sheetContext,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('New playlist'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: name,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: description,
                          decoration: const InputDecoration(
                            labelText: 'Description (optional)',
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          [name.text, description.text],
                        ),
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                );
                name.dispose();
                description.dispose();
                if (result == null ||
                    result.first.trim().isEmpty ||
                    !sheetContext.mounted) {
                  return;
                }
                final created = await provider.createPlaylist(
                  result.first,
                  description: result.length > 1 ? result[1] : null,
                );
                if (created != null && sheetContext.mounted) {
                  Navigator.pop(sheetContext, created);
                }
              },
            ),
            ...provider.playlists.map(
              (playlist) => ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name),
                subtitle: Text('${playlist.songIds.length} songs'),
                onTap: () => Navigator.pop(sheetContext, playlist),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await provider.addSong(selected.id, song);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to ${selected.name}')),
      );
    }
  }

  Future<void> _chooseFolders() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LibraryManagementScreen()),
    );
    if (!mounted) return;
    await context.read<LibraryProvider>().loadAllSongs();
    await _refreshFolderVisibility();
  }

  @override
  Widget build(BuildContext context) {
    return ResonateGlassScaffold(
      title: Text(_selectMode ? '${_selectedIds.length} selected' : 'Library'),
      actions: [
        if (_selectMode) ...[
          IconButton(
            tooltip: 'Cancel selection',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _toggleSelectMode(false),
          ),
        ] else ...[
          IconButton(
            tooltip: 'Select',
            icon: const Icon(Icons.checklist_rounded),
            onPressed: () => _toggleSelectMode(true),
          ),
          IconButton(
            tooltip: 'Liked Songs',
            icon: const Icon(Icons.favorite_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Playlists',
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              final library = context.read<LibraryProvider>();
              await library.loadAllSongs();
              await library.loadFavoriteSongs();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Library refreshed')),
                );
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              final library = context.read<LibraryProvider>();
              if (const ['title', 'artist', 'album', 'date_added', 'duration'].contains(value)) {
                library.setSortBy(value);
              }
              if (const ['all', 'favorites', 'recent'].contains(value)) {
                library.setFilterBy(value);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'title', child: Text('Sort by Title')),
              PopupMenuItem(value: 'artist', child: Text('Sort by Artist')),
              PopupMenuItem(value: 'album', child: Text('Sort by Album')),
              PopupMenuItem(
                value: 'date_added',
                child: Text('Sort by Date Added'),
              ),
              PopupMenuItem(
                value: 'duration',
                child: Text('Sort by Duration'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(value: 'all', child: Text('Filter: All')),
              PopupMenuItem(
                value: 'favorites',
                child: Text('Filter: Favorites'),
              ),
              PopupMenuItem(value: 'recent', child: Text('Filter: Recent')),
            ],
          ),
        ],
      ],
      body: Column(
        children: [
          if (!_hasSelectedFolders)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: ResonateGlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('Choose a music folder'),
                  subtitle: const Text(
                    'Optional — tap to limit future scans to a folder.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _chooseFolders,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: _searchController.clear,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Consumer<LibraryProvider>(
            builder: (_, library, __) {
              final q = library.searchQuery.trim().toLowerCase();
              if (q.isEmpty) return const SizedBox.shrink();
              final artists = <String>{};
              final albums = <String>{};
              for (final s in library.filteredSongs.isNotEmpty
                  ? library.filteredSongs
                  : library.allSongs) {
                if (s.artist.toLowerCase().contains(q)) artists.add(s.artist);
                if (s.album.toLowerCase().contains(q)) albums.add(s.album);
                if (artists.length >= 8 && albums.length >= 8) break;
              }
              if (artists.isEmpty && albums.isEmpty) {
                return const SizedBox.shrink();
              }
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  children: [
                    for (final a in artists.take(6))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.person_rounded, size: 16),
                          label: Text(a, overflow: TextOverflow.ellipsis),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ArtistScreen(artist: a),
                              ),
                            );
                          },
                        ),
                      ),
                    for (final al in albums.take(6))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.album_rounded, size: 16),
                          label: Text(al, overflow: TextOverflow.ellipsis),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AlbumScreen(album: al),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          Consumer<LibraryProvider>(
            builder: (_, library, __) {
              final songs = library.filteredSongs.isNotEmpty ||
                      library.searchQuery.isNotEmpty ||
                      library.filterBy != 'all'
                  ? library.filteredSongs
                  : library.allSongs;
              final total = _totalDuration(songs);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      value: '${library.statistics['totalSongs'] ?? songs.length}',
                      label: 'Songs',
                    ),
                    _StatItem(
                      value: '${library.statistics['favoriteCount'] ?? 0}',
                      label: 'Liked',
                    ),
                    _StatItem(
                      value: '${library.statistics['totalPlaylists'] ?? 0}',
                      label: 'Playlists',
                    ),
                    _StatItem(
                      value: _formatDuration(total),
                      label: 'Total',
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      final library = context.read<LibraryProvider>();
                      final songs = library.filteredSongs.isNotEmpty ||
                              library.searchQuery.isNotEmpty ||
                              library.filterBy != 'all'
                          ? library.filteredSongs
                          : library.allSongs;
                      if (songs.isEmpty) return;
                      final music = context.read<MusicProvider>();
                      await music.setShuffleEnabled(false);
                      await music.playSong(
                        songs.first,
                        queue: List.from(songs),
                        startIndex: 0,
                      );
                      if (mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PlayerScreen()),
                        );
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play all'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      final library = context.read<LibraryProvider>();
                      final songs = List.of(
                        library.filteredSongs.isNotEmpty ||
                                library.searchQuery.isNotEmpty ||
                                library.filterBy != 'all'
                            ? library.filteredSongs
                            : library.allSongs,
                      );
                      if (songs.isEmpty) return;
                      songs.shuffle();
                      final music = context.read<MusicProvider>();
                      await music.setShuffleEnabled(true);
                      await music.playSong(
                        songs.first,
                        queue: songs,
                        startIndex: 0,
                      );
                      if (mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PlayerScreen()),
                        );
                      }
                    },
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Shuffle'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          if (_selectMode)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        final library = context.read<LibraryProvider>();
                        final songs = library.filteredSongs.isNotEmpty ||
                                library.searchQuery.isNotEmpty ||
                                library.filterBy != 'all'
                            ? library.filteredSongs
                            : library.allSongs;
                        setState(() {
                          if (_selectedIds.length == songs.length) {
                            _selectedIds.clear();
                          } else {
                            _selectedIds
                              ..clear()
                              ..addAll(songs.map((s) => s.id));
                          }
                        });
                      },
                      child: const Text('All'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () {
                              final library = context.read<LibraryProvider>();
                              final songs = library.filteredSongs.isNotEmpty ||
                                      library.searchQuery.isNotEmpty ||
                                      library.filterBy != 'all'
                                  ? library.filteredSongs
                                  : library.allSongs;
                              _batchPlayNext(songs);
                            },
                      icon: const Icon(Icons.playlist_play_rounded),
                      label: const Text('Next'),
                    ),
                    TextButton.icon(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () {
                              final library = context.read<LibraryProvider>();
                              final songs = library.filteredSongs.isNotEmpty ||
                                      library.searchQuery.isNotEmpty ||
                                      library.filterBy != 'all'
                                  ? library.filteredSongs
                                  : library.allSongs;
                              _batchAddToQueue(songs);
                            },
                      icon: const Icon(Icons.playlist_add_rounded),
                      label: const Text('Queue'),
                    ),
                    TextButton.icon(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () {
                              final library = context.read<LibraryProvider>();
                              final songs = library.filteredSongs.isNotEmpty ||
                                      library.searchQuery.isNotEmpty ||
                                      library.filterBy != 'all'
                                  ? library.filteredSongs
                                  : library.allSongs;
                              _batchAddToPlaylist(songs);
                            },
                      icon: const Icon(Icons.queue_music_rounded),
                      label: const Text('Playlist'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Consumer2<LibraryProvider, MusicProvider>(
              builder: (context, library, music, _) {
                final songs =
                    library.filteredSongs.isNotEmpty ||
                        library.searchQuery.isNotEmpty ||
                        library.filterBy != 'all'
                    ? library.filteredSongs
                    : library.allSongs;
                if (songs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No songs found. Choose a music folder or scan your library.',
                    ),
                  );
                }
                final nowPlaying = music.currentSong;
                return Column(
                  children: [
                    if (nowPlaying != null)
                      Material(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.55),
                        child: ListTile(
                          leading: Icon(
                            music.isPlaying
                                ? Icons.graphic_eq_rounded
                                : Icons.pause_circle_outline_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            nowPlaying.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Now playing · ${nowPlaying.artist}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () async {
                            if (music.isPlaying) {
                              await music.togglePlayPause();
                            } else if (music.queue.isNotEmpty &&
                                music.queueIndex >= 0) {
                              await music.playSong(
                                nowPlaying,
                                queue: music.queue,
                                startIndex: music.queueIndex,
                              );
                            }
                          },
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: songs.length,
                        itemBuilder: (_, index) {
                          final song = songs[index];
                          final current = music.currentSong?.id == song.id;
                          final liked = library.isFavoriteSync(song.id);
                          return ListTile(
                            selected: current ||
                                (_selectMode && _selectedIds.contains(song.id)),
                            leading: _selectMode
                                ? Checkbox(
                                    value: _selectedIds.contains(song.id),
                                    onChanged: (_) => _toggleSelected(song.id),
                                  )
                                : Icon(
                                    current && music.isPlaying
                                        ? Icons.equalizer_rounded
                                        : Icons.music_note_rounded,
                                    color: current
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
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
                                if (!_selectMode)
                                  PopupMenuButton<String>(
                                    tooltip: 'More',
                                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                                    onSelected: (value) async {
                                      if (value == 'play_next') {
                                        final music = context.read<MusicProvider>();
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
                                      } else if (value == 'queue') {
                                        await _addToQueueWithHaptic(song);
                                      } else if (value == 'artist') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ArtistScreen(artist: song.artist),
                                          ),
                                        );
                                      } else if (value == 'album') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AlbumScreen(
                                              album: song.album,
                                              artistHint: song.artist,
                                            ),
                                          ),
                                        );
                                      } else if (value == 'playlist') {
                                        _addToPlaylist(song);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'play_next',
                                        child: Text('Play next'),
                                      ),
                                      PopupMenuItem(
                                        value: 'queue',
                                        child: Text('Add to queue'),
                                      ),
                                      PopupMenuItem(
                                        value: 'artist',
                                        child: Text('Go to artist'),
                                      ),
                                      PopupMenuItem(
                                        value: 'album',
                                        child: Text('Go to album'),
                                      ),
                                      PopupMenuItem(
                                        value: 'playlist',
                                        child: Text('Add to playlist'),
                                      ),
                                    ],
                                  ),
                                Text(
                                  _formatDuration(song.duration),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                                IconButton(
                                  tooltip: liked ? 'Unlike' : 'Like',
                                  icon: Icon(
                                    liked
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: liked
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                  onPressed: () => library.toggleFavorite(song),
                                ),
                              ],
                            ),
                            onTap: () {
                              if (_selectMode) {
                                _toggleSelected(song.id);
                                return;
                              }
                              _playSong(songs, index);
                            },
                            onLongPress: () {
                              if (_selectMode) {
                                _toggleSelected(song.id);
                                return;
                              }
                              _addToQueueWithHaptic(song);
                            },
                          );
                        },
                      ),
                    ),
                  ],
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
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
