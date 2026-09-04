import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/music_provider.dart';
import '../providers/library_provider.dart';
import '../providers/playlist_provider.dart';
import 'player_screen.dart';
import 'playlists_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);
  @override State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  @override void initState() { super.initState(); _searchController.addListener(_onSearchChanged); }
  void _onSearchChanged() { context.read<LibraryProvider>().searchSongs(_searchController.text); setState(() {}); }

  Future<void> _playSong(BuildContext context, List<Song> songs, int index) async {
    final music = context.read<MusicProvider>();
    final library = context.read<LibraryProvider>();
    final song = songs[index];
    final success = await music.playSong(song, queue: List.from(songs), startIndex: index);
    if (!mounted) return;
    if (success) { await library.updatePlayCount(song.id); if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())); }
    else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to play this song. Check that the music file is still available.')));
  }

  Future<void> _addToPlaylist(Song song) async {
    final provider = context.read<PlaylistProvider>();
    if (provider.playlists.isEmpty) await provider.loadPlaylists();
    if (!mounted) return;
    final playlist = await showModalBottomSheet<Playlist>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Add to playlist'), subtitle: Text('Choose where to save this song.')),
          ListTile(
            leading: const Icon(Icons.add_rounded), title: const Text('Create new playlist'),
            onTap: () async {
              final name = TextEditingController();
              final description = TextEditingController();
              final result = await showDialog<List<String>>(
                context: sheetContext,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('New playlist'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
                    const SizedBox(height: 12),
                    TextField(controller: description, decoration: const InputDecoration(labelText: 'Description (optional)')),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(dialogContext, [name.text, description.text]), child: const Text('Create')),
                  ],
                ),
              );
              name.dispose();
              description.dispose();
              if (result == null || result.first.trim().isEmpty || !sheetContext.mounted) return;
              final created = await provider.createPlaylist(result.first, description: result.length > 1 ? result[1] : null);
              if (created != null && sheetContext.mounted) Navigator.pop(sheetContext, created);
            },
          ),
          ...provider.playlists.map((playlist) => ListTile(
            leading: const Icon(Icons.queue_music_rounded), title: Text(playlist.name), subtitle: Text('${playlist.songIds.length} songs'),
            onTap: () => Navigator.pop(sheetContext, playlist),
          )),
        ]),
      ),
    );
    if (playlist == null || !mounted) return;
    await provider.addSong(playlist.id, song);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to ${playlist.name}')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Library'),
      actions: [
        IconButton(tooltip: 'Playlists', icon: const Icon(Icons.queue_music_rounded), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaylistsScreen()))),
        IconButton(icon: const Icon(Icons.refresh), onPressed: () async { final p = context.read<LibraryProvider>(); await p.loadAllSongs(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Library refreshed'))); }),
        PopupMenuButton<String>(onSelected: (value) { final p = context.read<LibraryProvider>(); if (['title', 'artist', 'album', 'date_added'].contains(value)) p.setSortBy(value); if (['all', 'favorites', 'recent'].contains(value)) p.setFilterBy(value); }, itemBuilder: (_) => const [PopupMenuItem(value: 'title', child: Text('Sort by Title')), PopupMenuItem(value: 'artist', child: Text('Sort by Artist')), PopupMenuItem(value: 'album', child: Text('Sort by Album')), PopupMenuItem(value: 'date_added', child: Text('Sort by Date Added')), PopupMenuDivider(), PopupMenuItem(value: 'all', child: Text('Filter: All')), PopupMenuItem(value: 'favorites', child: Text('Filter: Favorites')), PopupMenuItem(value: 'recent', child: Text('Filter: Recent'))]),
      ],
    ),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _searchController, decoration: InputDecoration(hintText: 'Search songs, artists, albums...', prefixIcon: const Icon(Icons.search), suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: _searchController.clear) : null, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
      Consumer<LibraryProvider>(builder: (context, p, _) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_StatItem(value: '${p.statistics['totalSongs'] ?? 0}', label: 'Songs'), _StatItem(value: '${p.statistics['favoriteCount'] ?? 0}', label: 'Favorites'), _StatItem(value: '${p.statistics['totalPlaylists'] ?? 0}', label: 'Playlists')]))),
      const Divider(),
      Expanded(child: Consumer2<LibraryProvider, MusicProvider>(builder: (context, library, music, _) {
        final songs = library.filteredSongs.isNotEmpty || library.searchQuery.isNotEmpty || library.filterBy != 'all' ? library.filteredSongs : library.allSongs;
        if (songs.isEmpty) return const Center(child: Text('No songs found. Add a music folder in Library Management.'));
        return ListView.builder(itemCount: songs.length, itemBuilder: (context, index) {
          final song = songs[index];
          final isCurrent = music.currentSong?.id == song.id;
          return ListTile(
            leading: Icon(isCurrent && music.isPlaying ? Icons.equalizer_rounded : Icons.music_note, color: isCurrent ? Theme.of(context).colorScheme.primary : null),
            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis), selected: isCurrent,
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'favorite') await library.addFavorite(song);
                if (value == 'next') { final added = await music.playNext(song); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? 'Playing next: ${song.title}' : 'Song is already in the queue'))); }
                if (value == 'queue') { final added = await music.addToQueue(song); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? 'Added to queue' : 'Song is already in the queue'))); }
                if (value == 'playlist') await _addToPlaylist(song);
                if (value == 'delete') await library.deleteSong(song.id);
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'favorite', child: Text('Add to favorites')), PopupMenuItem(value: 'next', child: Text('Play next')), PopupMenuItem(value: 'queue', child: Text('Add to queue')), PopupMenuItem(value: 'playlist', child: Text('Add to playlist')), PopupMenuItem(value: 'delete', child: Text('Remove from library'))],
            ),
            onTap: () => _playSong(context, songs, index),
          );
        });
      })),
    ]),
  );

  @override void dispose() { _searchController.removeListener(_onSearchChanged); _searchController.dispose(); super.dispose(); }
}

class _StatItem extends StatelessWidget {
  final String value; final String label;
  const _StatItem({required this.value, required this.label});
  @override Widget build(BuildContext context) => Column(children: [Text(value, style: Theme.of(context).textTheme.titleMedium), Text(label, style: Theme.of(context).textTheme.bodySmall)]);
}
