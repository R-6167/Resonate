import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/intelligence_recommendation.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../providers/library_provider.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget { const HomeScreen({Key? key}) : super(key: key); @override State<HomeScreen> createState() => _HomeScreenState(); }
class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final _screens = const [_HomeDashboard(), LibraryScreen(), PlayerScreen(), SettingsScreen()];
  @override Widget build(BuildContext context) => Scaffold(body: _screens[_selectedIndex], bottomNavigationBar: NavigationBar(selectedIndex: _selectedIndex, onDestinationSelected: (i) => setState(() => _selectedIndex = i), destinations: const [
    NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'For You'),
    NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
    NavigationDestination(icon: Icon(Icons.music_note_outlined), selectedIcon: Icon(Icons.music_note), label: 'Player'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
  ]));
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard();
  @override Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final music = context.watch<MusicProvider>();
    final intelligence = context.watch<IntelligenceProvider>();
    final songs = library.allSongs;
    final next = intelligence.anticipatedNext;
    return Scaffold(
      appBar: AppBar(title: const _ResonateWordmark()),
      body: RefreshIndicator(onRefresh: intelligence.refreshRecommendations, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(18, 8, 18, 34), children: [
        Text('Good listening.', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 4),
        Text('Your library, with a little intuition.', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 20),
        _IntelligenceHero(intelligence: intelligence, songCount: songs.length),
        const SizedBox(height: 24),
        if (music.currentSong != null) ...[
          _sectionTitle(context, 'Now playing'),
          Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), leading: CircleAvatar(radius: 24, child: Icon(music.isPlaying ? Icons.graphic_eq : Icons.pause_rounded)), title: Text(music.currentSong!.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(music.currentSong!.artist, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: FilledButton.tonalIcon(onPressed: music.togglePlayPause, icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(music.isPlaying ? 'Pause' : 'Play')), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())))),
          const SizedBox(height: 24),
        ],
        if (intelligence.isEnabled && next != null) ...[
          _sectionTitle(context, intelligence.isAutopilot ? 'Autopilot is choosing next' : 'What should play next?'),
          _AnticipationCard(item: next, songs: songs, autopilot: intelligence.isAutopilot),
          const SizedBox(height: 24),
        ],
        _sectionTitle(context, intelligence.isEnabled ? 'Other good bets' : 'Suggested from your library'),
        if (intelligence.isEnabled && intelligence.recommendations.length > 1)
          ...intelligence.recommendations.skip(1).map((item) => _RecommendationTile(item: item, songs: songs))
        else if (!intelligence.isEnabled)
          Card(child: ListTile(leading: const Icon(Icons.auto_awesome_outlined), title: const Text('Intelligence is off'), subtitle: Text('Your player remains fully manual. Enable it from Settings when you want local anticipation.', style: Theme.of(context).textTheme.bodyMedium)))
        else
          Card(child: ListTile(leading: const Icon(Icons.headphones_rounded), title: Text(songs.length < 5 ? 'Let Resonate learn you' : 'Building your first prediction'), subtitle: Text('Finishes, skips and song-to-song choices become local signals for future decisions.', style: Theme.of(context).textTheme.bodyMedium))),
      ])),
    );
  }
  Widget _sectionTitle(BuildContext context, String text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(text, style: Theme.of(context).textTheme.titleLarge));
}

class _ResonateWordmark extends StatelessWidget {
  const _ResonateWordmark();
  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ShaderMask(shaderCallback: (bounds) => LinearGradient(colors: [scheme.primary, scheme.secondary]).createShader(bounds), child: Text('Resonate', style: TextStyle(fontFamily: 'serif', fontSize: 27, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -1.4, color: Colors.white)));
  }
}

class _IntelligenceHero extends StatelessWidget {
  final IntelligenceProvider intelligence; final int songCount;
  const _IntelligenceHero({required this.intelligence, required this.songCount});
  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final autopilot = intelligence.isAutopilot;
    final graduated = intelligence.isAutopilotGraduated;
    final title = autopilot ? 'Autopilot is active.' : graduated ? 'I have learned enough to take the wheel.' : 'I think I know what you want next.';
    final description = autopilot
        ? 'I will keep your session moving with local predictions while you listen. Turn Intelligence off any time to return to normal manual playback.'
        : 'I watch your local listening patterns and make one strongest prediction instead of asking you to browse a wall of recommendations.';
    return Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHighest]), border: Border.all(color: scheme.outlineVariant.withOpacity(.45))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)), child: Icon(autopilot ? Icons.smart_toy_rounded : Icons.auto_awesome, color: scheme.onPrimary)), const SizedBox(width: 12), Expanded(child: Text('Resonate Intelligence', style: Theme.of(context).textTheme.titleLarge)), Text(intelligence.isEnabled ? intelligence.autonomyLabel : 'OFF', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary))]),
      const SizedBox(height: 16),
      Text(intelligence.isEnabled ? title : 'Your player is fully manual.', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 7),
      Text(intelligence.isEnabled ? description : 'Intelligence is disabled. Nothing will learn, predict or alter your playback.', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [if (autopilot) const _Tag(label: 'Autopilot active') else if (graduated) const _Tag(label: 'Graduated'), const _Tag(label: 'Local-first'), const _Tag(label: 'Explainable'), _Tag(label: '$songCount songs')]),
    ]));
  }
}
class _Tag extends StatelessWidget { final String label; const _Tag({required this.label}); @override Widget build(BuildContext context) => Chip(label: Text(label), visualDensity: VisualDensity.compact); }

class _FeedbackButtons extends StatelessWidget {
  final String songId;
  const _FeedbackButtons({required this.songId});
  @override Widget build(BuildContext context) {
    final intelligence = context.read<IntelligenceProvider>();
    final value = intelligence.feedbackFor(songId);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(tooltip: 'Good recommendation', isSelected: value > 0, onPressed: () => intelligence.rateRecommendation(songId, true), icon: const Icon(Icons.thumb_up_outlined), selectedIcon: const Icon(Icons.thumb_up)),
      IconButton(tooltip: 'Not for me', isSelected: value < 0, onPressed: () => intelligence.rateRecommendation(songId, false), icon: const Icon(Icons.thumb_down_outlined), selectedIcon: const Icon(Icons.thumb_down)),
    ]);
  }
}

class _AnticipationCard extends StatelessWidget {
  final IntelligenceRecommendation item; final List<dynamic> songs; final bool autopilot;
  const _AnticipationCard({required this.item, required this.songs, this.autopilot = false});
  @override Widget build(BuildContext context) { final music = context.read<MusicProvider>(); final scheme = Theme.of(context).colorScheme; return Card(color: scheme.primaryContainer.withOpacity(.72), child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 10, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(autopilot ? Icons.smart_toy_rounded : Icons.auto_awesome, color: scheme.primary), const SizedBox(width: 8), Expanded(child: Text(autopilot ? 'Next-track decision' : item.confidenceLabel, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary))), Text('${(item.confidence * 100).round()}%', style: Theme.of(context).textTheme.labelLarge)]), const SizedBox(height: 9), Text(item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), Text(item.song.artist, maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 8), Text(item.reason, style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 10), Row(children: [Expanded(child: Text('Teach Intelligence', style: Theme.of(context).textTheme.labelMedium)), _FeedbackButtons(songId: item.song.id)]), Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: () async { final i = songs.indexWhere((s) => s.id == item.song.id); await music.playSong(item.song, queue: songs.cast(), startIndex: i < 0 ? 0 : i); }, icon: const Icon(Icons.play_arrow_rounded), label: Text(autopilot ? 'Play now' : 'Play this next')))]))); }
}
class _RecommendationTile extends StatelessWidget {
  final IntelligenceRecommendation item; final List<dynamic> songs;
  const _RecommendationTile({required this.item, required this.songs});
  @override Widget build(BuildContext context) { final music = context.read<MusicProvider>(); return Card(margin: const EdgeInsets.only(bottom: 9), child: ListTile(leading: CircleAvatar(radius: 25, child: const Icon(Icons.music_note_rounded)), title: Text(item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${item.song.artist}\n${item.reason}', maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium), trailing: Row(mainAxisSize: MainAxisSize.min, children: [_FeedbackButtons(songId: item.song.id), IconButton(tooltip: 'Play', icon: const Icon(Icons.play_arrow_rounded), onPressed: () async { final i = songs.indexWhere((s) => s.id == item.song.id); await music.playSong(item.song, queue: songs.cast(), startIndex: i < 0 ? 0 : i); })])); }
}
