import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/library_provider.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({Key? key}) : super(key: key);
  @override State<LibraryScreen> createState() => _LibraryScreenState();
}
class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  @override void initState() { super.initState(); _searchController.addListener(_onSearchChanged); }
  void _onSearchChanged() { context.read<LibraryProvider>().searchSongs(_searchController.text); setState(() {}); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Library'), actions: [
      IconButton(icon: const Icon(Icons.refresh), onPressed: () async { final p = context.read<LibraryProvider>(); await p.loadAllSongs(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Library refreshed'))); }),
      PopupMenuButton<String>(onSelected: (value) { final p = context.read<LibraryProvider>(); if (['title','artist','album','date_added'].contains(value)) p.setSortBy(value); if (['all','favorites','recent'].contains(value)) p.setFilterBy(value); }, itemBuilder: (_) => const [
        PopupMenuItem(value: 'title', child: Text('Sort by Title')), PopupMenuItem(value: 'artist', child: Text('Sort by Artist')), PopupMenuItem(value: 'album', child: Text('Sort by Album')), PopupMenuItem(value: 'date_added', child: Text('Sort by Date Added')), PopupMenuDivider(), PopupMenuItem(value: 'all', child: Text('Filter: All')), PopupMenuItem(value: 'favorites', child: Text('Filter: Favorites')), PopupMenuItem(value: 'recent', child: Text('Filter: Recent')),
      ]),
    ]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _searchController, decoration: InputDecoration(hintText: 'Search songs, artists, albums...', prefixIcon: const Icon(Icons.search), suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: _searchController.clear) : null, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
      Consumer<LibraryProvider>(builder: (context, p, _) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_StatItem(value: '${p.statistics['totalSongs'] ?? 0}', label: 'Songs'), _StatItem(value: '${p.statistics['favoriteCount'] ?? 0}', label: 'Favorites'), _StatItem(value: '${p.statistics['totalPlaylists'] ?? 0}', label: 'Playlists')]))) ,
      const Divider(),
      Expanded(child: Consumer2<LibraryProvider, MusicProvider>(builder: (context, library, music, _) {
        final songs = library.filteredSongs.isNotEmpty || library.searchQuery.isNotEmpty || library.filterBy != 'all' ? library.filteredSongs : library.allSongs;
        if (songs.isEmpty) return const Center(child: Text('No songs found. Add a music folder in Library Management.'));
        return ListView.builder(itemCount: songs.length, itemBuilder: (context, index) { final song = songs[index]; final isCurrent = music.currentSong?.id == song.id; return ListTile(
          leading: Icon(Icons.music_note, color: isCurrent ? Theme.of(context).colorScheme.primary : null), title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis), selected: isCurrent,
          trailing: PopupMenuButton<String>(onSelected: (value) async { if (value == 'favorite') await library.addFavorite(song); if (value == 'delete') await library.deleteSong(song.id); }, itemBuilder: (_) => const [PopupMenuItem(value: 'favorite', child: Text('Add to favorites')), PopupMenuItem(value: 'delete', child: Text('Remove from library'))]),
          onTap: () async { await music.setQueue(songs, startIndex: index); await music.playSong(song); await library.updatePlayCount(song.id); if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())); },
        ); });
      })),
    ]),
  );
  @override void dispose() { _searchController.removeListener(_onSearchChanged); _searchController.dispose(); super.dispose(); }
}
class _StatItem extends StatelessWidget { final String value; final String label; const _StatItem({required this.value, required this.label}); @override Widget build(BuildContext context) => Column(children: [Text(value, style: Theme.of(context).textTheme.titleMedium), Text(label, style: Theme.of(context).textTheme.bodySmall)]); }
