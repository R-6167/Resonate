import 'package:flutter/material.dart';
import '../ui/resonate_glass.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import '../providers/intelligence_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../services/playback_authority.dart';
import '../widgets/evolving_mix_card.dart';
import '../widgets/autopilot_home_card.dart';
import '../widgets/ask_resonate_sheet.dart';
import '../widgets/resonate_logo.dart';
import '../widgets/dj_mode_status_chip.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

String _homeFormatClock(int ms) {
  final totalSec = (ms / 1000).floor().clamp(0, 24 * 3600);
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _homeFormatDuration(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 1) return '${d.inSeconds}s';
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _pageController;
  int _selectedIndex = 0;

  static const _screens = [
    _HomeDashboard(),
    LibraryScreen(),
    PlayerScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // FAB on For You (0), Library (1), Player (2) — not Settings (3).
    final showAsk = _selectedIndex <= 2;

    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        itemCount: _screens.length,
        onPageChanged: (index) => setState(() => _selectedIndex = index),
        itemBuilder: (_, index) => _screens[index],
      ),
      floatingActionButton: showAsk ? const AskResonateFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectPage,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'For You'),
          NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.music_note_outlined), selectedIcon: Icon(Icons.music_note), label: 'Player'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard();

  List<Widget> _recommendations(IntelligenceProvider intelligence, List<dynamic> songs) {
    if (!intelligence.isEnabled) {
      return const [ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Intelligence is off'), subtitle: Text('Your player remains fully manual. Enable it from Settings when you want local anticipation.')))];
    }
    final recommendations = intelligence.recommendations.skip(1).toList();
    if (recommendations.isEmpty) {
      return const [ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(leading: Icon(Icons.headphones_rounded), title: Text('Let Resonate get to know your taste'), subtitle: Text('Finishes, skips and song-to-song choices become local signals for future decisions.')))];
    }
    return recommendations.map<Widget>((item) => _RecommendationTile(item: item, songs: songs)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final music = context.watch<MusicProvider>();
    final intelligence = context.watch<IntelligenceProvider>();
    final songs = library.allSongs;
    final recommendationQueue = intelligence.recommendations.map((item) => item.song).toList();
    final children = <Widget>[
      const SizedBox(height: 6),
      // Combined Intelligence + Autopilot + nudge (single card, no duplicate sections)
      AutopilotHomeCard(songCount: songs.length),
    ];

    if (music.canContinueListening && music.currentSong != null && !music.isPlaying) {
      final song = music.currentSong!;
      final pos = music.resumePositionMs;
      final dur = (music.currentDuration ?? song.duration).inMilliseconds;
      final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
      children.addAll([
        const SizedBox(height: 14),
        ResonateGlassCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.history_rounded)),
            title: const Text('Continue listening', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${song.title}\n${_homeFormatClock(pos)} / ${_homeFormatClock(dur)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: FilledButton.tonalIcon(
              onPressed: () => music.continueListening(),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume'),
            ),
            onTap: () => music.continueListening(),
          ),
        ),
        if (progress > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: LinearProgressIndicator(value: progress, minHeight: 3),
          ),
      ]);
    }

    if (intelligence.isEnabled) {
      children.addAll([
        const SizedBox(height: 16),
        const EvolvingMixCard(),
      ]);
    }

    if (music.currentSong != null) {
      children.addAll([
        const SizedBox(height: 20),
        _sectionTitle(context, 'Now playing'),
        ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(
          leading: CircleAvatar(child: Icon(music.isPlaying ? Icons.graphic_eq : Icons.pause_rounded)),
          title: Text(music.currentSong!.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(music.currentSong!.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              const DjModeStatusChip(dense: true),
            ],
          ),
          isThreeLine: true,
          trailing: FilledButton.tonalIcon(onPressed: () => PlaybackAuthority.instance.userToggle(music), icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(music.isPlaying ? 'Pause' : 'Play')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())),
        )),
      ]);
    }

    // “More music…” keeps additional recommendations (skip #1 is already the nudge inside the card)
    children.addAll([
      const SizedBox(height: 20),
      _sectionTitle(context, intelligence.isEnabled ? 'More music for this moment' : 'Suggested from your library'),
      ..._recommendations(intelligence, recommendationQueue.isEmpty ? songs : recommendationQueue),
      const SizedBox(height: 30),
    ]);

    return ResonateGlassScaffold(
      title: const ResonateLogo(size: 48),
      body: RefreshIndicator(
        onRefresh: intelligence.refreshRecommendations,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 34), children: children),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      );
}
