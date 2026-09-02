import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/library_provider.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'library_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final _screens = const [_HomeDashboard(), LibraryScreen(), PlayerScreen(), SettingsScreen()];
  @override Widget build(BuildContext context) => Scaffold(
    body: _screens[_selectedIndex],
    bottomNavigationBar: NavigationBar(selectedIndex: _selectedIndex, onDestinationSelected: (i) => setState(() => _selectedIndex = i), destinations: const [
      NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'For You'),
      NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
      NavigationDestination(icon: Icon(Icons.music_note_outlined), selectedIcon: Icon(Icons.music_note), label: 'Player'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
    ]),
  );
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard();
  @override Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final music = context.watch<MusicProvider>();
    final songs = library.allSongs;
    final recommendations = <dynamic>[];
    final seen = <String>{};
    for (final song in library.favoriteSongs.followedBy(songs)) { if (seen.add(song.id)) recommendations.add(song); if (recommendations.length >= 8) break; }
    return Scaffold(
      appBar: AppBar(title: const Text('Resonate'), actions: [IconButton(icon: const Icon(Icons.folder_open_outlined), tooltip: 'Manage Library', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryManagementScreen())))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 30), children: [
        Text('For You', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text('Your music, continuously shaped by the way you listen.', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 18),
        Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 10), Text('Resonate Intelligence', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 10),
          Text(songs.length < 5 ? 'Intelligence is getting started. Listen, skip and favorite tracks so Resonate can learn your taste.' : 'Your library is ready. Resonate can progressively learn your patterns and build better next-song suggestions locally.'),
          const SizedBox(height: 12),
          Text('Local-first • explainable • lightweight', style: Theme.of(context).textTheme.labelMedium),
        ]))),
        const SizedBox(height: 22),
        if (music.currentSong != null) ...[
          _heading(context, 'Continue Listening'),
          Card(child: ListTile(leading: const Icon(Icons.play_circle_fill, size: 42), title: Text(music.currentSong!.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(music.currentSong!.artist), trailing: IconButton(icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow), onPressed: music.togglePlayPause), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())))),
          const SizedBox(height: 22),
        ],
        _heading(context, 'Suggested for You'),
        if (recommendations.isEmpty)
          Card(child: ListTile(leading: const Icon(Icons.library_music_outlined), title: const Text('Start building your library'), subtitle: const Text('Choose folders in Library Management, then scan them.'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryManagementScreen()))))
        else
          ...recommendations.map((song) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: const CircleAvatar(child: Icon(Icons.music_note)), title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: const Icon(Icons.play_arrow), onTap: () async {
            final index = songs.indexWhere((item) => item.id == song.id);
            await music.setQueue(songs, startIndex: index < 0 ? 0 : index);
            await music.playSong(song);
            if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
          }))),
      ]),
    );
  }
  Widget _heading(BuildContext context, String text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)));
}
