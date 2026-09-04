import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../providers/playlist_provider.dart';
import 'player_screen.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final description = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New playlist'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(controller: description, decoration: const InputDecoration(labelText: 'Description (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, [name.text, description.text]), child: const Text('Create')),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    if (result == null || result.first.trim().isEmpty || !context.mounted) return;
    await context.read<PlaylistProvider>().createPlaylist(result.first, description: result.length > 1 ? result[1] : null);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Playlists'), actions: [IconButton(onPressed: () => _create(context), icon: const Icon(Icons.add_rounded), tooltip: 'Create playlist')]),
    body: Consumer<PlaylistProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.playlists.isEmpty) return const Center(child: CircularProgressIndicator());
        if (provider.playlists.isEmpty) {
          return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.queue_music_rounded, size: 64),
            const SizedBox(height: 16),
            Text('Your playlists', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Create playlists that Resonate can learn from and build on.', textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.add), label: const Text('Create playlist')),
          ])));
        }
        return RefreshIndicator(onRefresh: provider.loadPlaylists, child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: provider.playlists.length, itemBuilder: (context, index) {
          final playlist = provider.playlists[index];
          return Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.queue_music_rounded)),
            title: Text(playlist.name),
            subtitle: Text('${playlist.songIds.length} songs${playlist.description == null ? '' : ' • ${playlist.description}'}', maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: playlist))),
            trailing: PopupMenuButton<String>(onSelected: (value) async {
              if (value == 'rename') await _rename(context, playlist);
              if (value == 'delete') await _delete(context, playlist);
            }, itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'delete', child: Text('Delete'))]),
          ));
        }));
      },
    ),
  );

  Future<void> _rename(BuildContext context, Playlist playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final value = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Rename playlist'), content: TextField(controller: controller, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save'))]));
    controller.dispose();
    if (value == null || value.trim().isEmpty || !context.mounted) return;
    await context.read<PlaylistProvider>().renamePlaylist(playlist.id, value);
  }

  Future<void> _delete(BuildContext context, Playlist playlist) async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete playlist?'), content: Text('Delete “${playlist.name}”? The songs stay in your library.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (confirmed == true && context.mounted) await context.read<PlaylistProvider>().deletePlaylist(playlist.id);
  }
}

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});
  @override State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late Future<List<Song>> _songs;

  @override
  void initState() {
    super.initState();
    _songs = context.read<PlaylistProvider>().songsFor(widget.playlist.id);
  }

  Future<void> _refresh() async => setState(() { _songs = context.read<PlaylistProvider>().songsFor(widget.playlist.id); });

  Future<void> _addSongs() async {
    final library = context.read<LibraryProvider>();
    final selected = <String>{};
    final songs = await showDialog<List<Song>>(context: context, builder: (_) => _SongPicker(songs: library.allSongs, initiallySelected: widget.playlist.songIds.toSet()));
    if (songs == null || !mounted) return;
    await context.read<PlaylistProvider>().addSongs(widget.playlist.id, songs.where((s) => !selected.contains(s.id)).toList());
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.playlist.name), actions: [IconButton(onPressed: _addSongs, icon: const Icon(Icons.add_rounded), tooltip: 'Add songs')]),
    body: FutureBuilder<List<Song>>(future: _songs, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      final songs = snapshot.data ?? const <Song>[];
      if (songs.isEmpty) return const Center(child: Text('No songs yet. Tap + to add songs.'));
      return ReorderableListView.builder(itemCount: songs.length, onReorder: (oldIndex, newIndex) async {
        if (newIndex > oldIndex) newIndex--;
        await context.read<PlaylistProvider>().reorderSong(widget.playlist.id, songs[oldIndex].id, newIndex);
        await _refresh();
      }, itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(key: ValueKey(song.id), leading: const Icon(Icons.music_note_rounded), title: Text(song.title), subtitle: Text(song.artist), trailing: IconButton(icon: const Icon(Icons.remove_circle_outline), tooltip: 'Remove', onPressed: () async { await context.read<PlaylistProvider>().removeSong(widget.playlist.id, song.id); await _refresh(); }), onTap: () async {
          await context.read<MusicProvider>().playSong(song, queue: songs, startIndex: index);
          if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
        });
      });
    }),
  );
}

class _SongPicker extends StatefulWidget {
  final List<Song> songs;
  final Set<String> initiallySelected;
  const _SongPicker({required this.songs, required this.initiallySelected});
  @override State<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends State<_SongPicker> {
  late final Set<String> _selected = {...widget.initiallySelected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.songs.where((song) => '${song.title} ${song.artist} ${song.album}'.toLowerCase().contains(_query.toLowerCase())).toList();
    return AlertDialog(title: const Text('Add songs'), content: SizedBox(width: 500, height: 520, child: Column(children: [TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search')), Expanded(child: ListView.builder(itemCount: visible.length, itemBuilder: (_, index) { final song = visible[index]; final checked = _selected.contains(song.id); return CheckboxListTile(value: checked, onChanged: (value) => setState(() { if (value == true) { _selected.add(song.id); } else { _selected.remove(song.id); } }), title: Text(song.title), subtitle: Text(song.artist)); }))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, widget.songs.where((song) => _selected.contains(song.id) && !widget.initiallySelected.contains(song.id)).toList()), child: Text('Add (${_selected.difference(widget.initiallySelected).length})'))]);
  }
}
