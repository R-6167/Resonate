import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/intelligence_recommendation.dart';
import '../providers/intelligence_provider.dart';
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

  @override
  Widget build(BuildContext context) => Scaffold(
        body: _screens[_selectedIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'For You'),
            NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.music_note_outlined), selectedIcon: Icon(Icons.music_note), label: 'Player'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      );
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final music = context.watch<MusicProvider>();
    final intelligence = context.watch<IntelligenceProvider>();
    final recommendations = intelligence.recommendations;
    final songs = library.allSongs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resonate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: 'Manage Library',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryManagementScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: intelligence.refreshRecommendations,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Good listening.', style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 4),
                  Text('Your library, with a little intuition.', style: Theme.of(context).textTheme.bodyLarge),
                ])),
                Switch(value: intelligence.isEnabled, onChanged: intelligence.setEnabled),
              ],
            ),
            const SizedBox(height: 18),
            _IntelligenceHero(intelligence: intelligence, songCount: songs.length),
            const SizedBox(height: 24),
            if (music.currentSong != null) ...[
              _sectionTitle(context, 'Now playing'),
              Card(child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: CircleAvatar(radius: 24, child: Icon(music.isPlaying ? Icons.graphic_eq : Icons.pause_rounded)),
                title: Text(music.currentSong!.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(music.currentSong!.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: FilledButton.tonalIcon(onPressed: music.togglePlayPause, icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(music.isPlaying ? 'Pause' : 'Play')),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())),
              )),
              const SizedBox(height: 24),
            ],
            _sectionTitle(context, intelligence.isEnabled ? 'Picked for you' : 'Suggested from your library'),
            if (intelligence.isEnabled && recommendations.isNotEmpty)
              ...recommendations.map((item) => _RecommendationTile(item: item, songs: songs))
            else if (!intelligence.isEnabled)
              const Card(child: ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Intelligence is off'), subtitle: Text('Turn it on to let Resonate learn your listening patterns and explain its picks.')))
            else
              Card(child: ListTile(
                leading: const Icon(Icons.headphones_rounded),
                title: Text(songs.length < 5 ? 'Let Resonate learn you' : 'Building your first mix'),
                subtitle: const Text('Listen naturally. Finishes, skips and song-to-song choices become local signals for future picks.'),
              )),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _IntelligenceHero extends StatelessWidget {
  final IntelligenceProvider intelligence;
  final int songCount;
  const _IntelligenceHero({required this.intelligence, required this.songCount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHighest]),
        border: Border.all(color: scheme.outlineVariant.withOpacity(.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)), child: Icon(Icons.auto_awesome, color: scheme.onPrimary)),
          const SizedBox(width: 12),
          Expanded(child: Text('Resonate Intelligence', style: Theme.of(context).textTheme.titleLarge)),
          Text(intelligence.isEnabled ? 'ON' : 'OFF', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
        ]),
        const SizedBox(height: 16),
        Text(
          intelligence.isEnabled
              ? 'It listens to how you listen.'
              : 'Your player works normally without Intelligence.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 7),
        Text(
          intelligence.isEnabled
              ? 'Local, lightweight and explainable. No cloud profile, no heavy model — just your listening history shaping the next song.'
              : 'Turn Intelligence back on whenever you want personalized suggestions and automatic next-song decisions.',
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Tag(label: 'Local-first'), _Tag(label: 'Explainable'), _Tag(label: '$songCount songs'),
        ]),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag({required this.label});
  @override Widget build(BuildContext context) => Chip(label: Text(label), visualDensity: VisualDensity.compact);
}

class _RecommendationTile extends StatelessWidget {
  final IntelligenceRecommendation item;
  final List<dynamic> songs;
  const _RecommendationTile({required this.item, required this.songs});

  @override
  Widget build(BuildContext context) {
    final music = context.read<MusicProvider>();
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          final index = songs.indexWhere((song) => song.id == item.song.id);
          final success = await music.playSong(item.song, queue: songs.cast(), startIndex: index < 0 ? 0 : index);
          if (!context.mounted) return;
          if (success) Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
        },
        child: Padding(padding: const EdgeInsets.fromLTRB(14, 13, 10, 13), child: Row(children: [
          CircleAvatar(radius: 25, child: const Icon(Icons.music_note_rounded)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(item.song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Row(children: [Icon(Icons.auto_awesome, size: 13, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4), Expanded(child: Text(item.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium))]),
          ])),
          IconButton(tooltip: 'Play', onPressed: () async {
            final index = songs.indexWhere((song) => song.id == item.song.id);
            await music.playSong(item.song, queue: songs.cast(), startIndex: index < 0 ? 0 : index);
          }, icon: const Icon(Icons.play_arrow_rounded)),
        ])),
      ),
    );
  }
}
