import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_recommendation.dart';
import '../providers/intelligence_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../services/playback_authority.dart';
import '../widgets/evolving_mix_card.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late final PageController _pageController;

  final List<Widget> _screens = const [
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
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        itemCount: _screens.length,
        onPageChanged: (index) => setState(() => _selectedIndex = index),
        itemBuilder: (_, index) => _screens[index],
      ),
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

class _HomeDashboard extends StatefulWidget {
  const _HomeDashboard();

  @override
  State<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<_HomeDashboard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final music = context.watch<MusicProvider>();
    final intelligence = context.watch<IntelligenceProvider>();
    final songs = library.allSongs;
    final recommendationQueue = intelligence.recommendations.map((item) => item.song).toList();
    final next = intelligence.anticipatedNext;

    return Scaffold(
      appBar: AppBar(title: const _ResonateWordmark()),
      body: RefreshIndicator(
        onRefresh: intelligence.refreshRecommendations,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back.', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('Something good is waiting in your library.', style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                ),
                _ListeningPulse(animation: _pulse),
              ],
            ),
            const SizedBox(height: 18),
            _IntelligenceHero(intelligence: intelligence, songCount: songs.length, animation: _pulse),
            if (intelligence.isEnabled) ...[
              const SizedBox(height: 16),
              _SessionCard(intelligence: intelligence),
              const SizedBox(height: 14),
              const EvolvingMixCard(),
            ],
            if (music.currentSong != null) ...[
              const SizedBox(height: 20),
              _sectionTitle(context, 'Now playing'),
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(music.isPlaying ? Icons.graphic_eq : Icons.pause_rounded)),
                  title: Text(music.currentSong!.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(music.currentSong!.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: FilledButton.tonalIcon(
                    onPressed: () => PlaybackAuthority.instance.userToggle(music),
                    icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(music.isPlaying ? 'Pause' : 'Play'),
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())),
                ),
              ),
            ],
            if (intelligence.isEnabled && next != null) ...[
              const SizedBox(height: 20),
              _sectionTitle(context, intelligence.isAutopilot ? 'Next up, intelligently' : 'A little nudge'),
              _AnticipationCard(item: next, songs: recommendationQueue.isEmpty ? songs : recommendationQueue),
            ],
            const SizedBox(height: 20),
            _sectionTitle(context, intelligence.isEnabled ? 'More music for this moment' : 'Suggested from your library'),
            if (!intelligence.isEnabled)
              const Card(child: ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Intelligence is off'), subtitle: Text('Your player remains fully manual. Enable it from Settings when you want local anticipation.')))
            else if (intelligence.recommendations.length > 1)
              ...intelligence.recommendations.skip(1).map((item) => _RecommendationTile(item: item, songs: recommendationQueue.isEmpty ? songs : recommendationQueue))
            else
              const Card(child: ListTile(leading: Icon(Icons.headphones_rounded), title: Text('Let Resonate get to know your taste'), subtitle: Text('Finishes, skips and song-to-song choices become local signals for future decisions.'))),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _ListeningPulse extends StatelessWidget {
  final Animation<double> animation;
  const _ListeningPulse({required this.animation});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 34,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: List.generate(3, (i) {
            final t = (animation.value + i * .18) % 1.0;
            final wave = .5 + .5 * (1 - (2 * t - 1).abs());
            return Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Opacity(
                opacity: .35 + .65 * wave,
                child: Transform.translate(
                  offset: Offset(0, 7 * (wave - .5)),
                  child: Container(width: 5, height: 5, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _ResonateWordmark extends StatelessWidget {
  const _ResonateWordmark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(colors: [scheme.primary, scheme.secondary]).createShader(bounds),
      child: const Text('Resonate', style: TextStyle(fontFamily: 'serif', fontSize: 27, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -1.4, color: Colors.white)),
    );
  }
}

class _IntelligenceHero extends StatelessWidget {
  final IntelligenceProvider intelligence;
  final int songCount;
  final Animation<double> animation;

  const _IntelligenceHero({required this.intelligence, required this.songCount, required this.animation});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final autopilot = intelligence.isAutopilot;
    final graduated = intelligence.isAutopilotGraduated;
    final title = autopilot ? 'You can just listen.' : graduated ? 'Resonate has your rhythm.' : 'Let Resonate learn your rhythm.';
    final description = autopilot ? 'Autopilot is quietly choosing what fits the session. You stay in control.' : 'Your listening patterns stay on this device and gradually shape what appears next.';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHighest]),
        border: Border.all(color: scheme.outlineVariant.withOpacity(.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: animation,
                builder: (_, __) {
                  final scale = .94 + animation.value * .06;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
                      child: Icon(autopilot ? Icons.smart_toy_rounded : Icons.auto_awesome, color: scheme.onPrimary),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Resonate Intelligence', style: Theme.of(context).textTheme.titleLarge)),
              Text(intelligence.isEnabled ? intelligence.autonomyLabel : 'OFF', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
            ],
          ),
          const SizedBox(height: 15),
          Text(intelligence.isEnabled ? title : 'Your player is fully manual.', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 7),
          Text(intelligence.isEnabled ? description : 'Intelligence is disabled. Nothing will learn, predict or alter your playback.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [if (autopilot) const _Tag(label: 'Autopilot active') else if (graduated) const _Tag(label: 'Graduated'), const _Tag(label: 'Local-first'), const _Tag(label: 'Explainable'), _Tag(label: '$songCount songs')]),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final IntelligenceProvider intelligence;
  const _SessionCard({required this.intelligence});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artists = intelligence.sessionArtists.take(3).join(' • ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(Icons.timeline_rounded, color: scheme.primary), const SizedBox(width: 9), Expanded(child: Text('Your listening flow', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))), Chip(label: Text(intelligence.sessionMode), visualDensity: VisualDensity.compact)]),
            const SizedBox(height: 8),
            Text(intelligence.sessionSummary),
            if (artists.isNotEmpty) ...[const SizedBox(height: 9), Text('Current flow: $artists', style: Theme.of(context).textTheme.labelMedium)],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag({required this.label});
  @override
  Widget build(BuildContext context) => Chip(label: Text(label), visualDensity: VisualDensity.compact);
}

class _AnticipationCard extends StatefulWidget {
  final IntelligenceRecommendation item;
  final List<dynamic> songs;
  const _AnticipationCard({required this.item, required this.songs});
  @override
  State<_AnticipationCard> createState() => _AnticipationCardState();
}

class _AnticipationCardState extends State<_AnticipationCard> {
  bool _loading = false;

  Future<void> _play() async {
    if (_loading) return;
    setState(() => _loading = true);
    final music = context.read<MusicProvider>();
    final index = widget.songs.indexWhere((song) => song.id == widget.item.song.id);
    try {
      await music.playSong(widget.item.song, queue: index >= 0 ? widget.songs.cast() : [widget.item.song], startIndex: index >= 0 ? index : 0);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confidence = (widget.item.confidence.clamp(0.0, 1.0) * 100).round();
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(.72),
      child: ListTile(
        leading: const Icon(Icons.auto_awesome),
        title: Text(widget.item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${widget.item.confidenceLabel} • $confidence%\n${widget.item.reason}', maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: _loading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(icon: const Icon(Icons.play_circle_fill_rounded), onPressed: _play),
        onTap: _loading ? null : _play,
      ),
    );
  }
}

class _RecommendationTile extends StatefulWidget {
  final IntelligenceRecommendation item;
  final List<dynamic> songs;
  const _RecommendationTile({required this.item, required this.songs});
  @override
  State<_RecommendationTile> createState() => _RecommendationTileState();
}

class _RecommendationTileState extends State<_RecommendationTile> {
  bool _loading = false;

  Future<void> _play() async {
    if (_loading) return;
    setState(() => _loading = true);
    final music = context.read<MusicProvider>();
    final index = widget.songs.indexWhere((song) => song.id == widget.item.song.id);
    try {
      await music.playSong(widget.item.song, queue: index >= 0 ? widget.songs.cast() : [widget.item.song], startIndex: index >= 0 ? index : 0);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, _) {
        final liked = library.isFavoriteSync(widget.item.song.id);
        final confidence = (widget.item.confidence.clamp(0.0, 1.0) * 100).round();
        return Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
            title: Text(widget.item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${widget.item.song.artist}\n${widget.item.confidenceLabel} • $confidence% • ${widget.item.reason}', maxLines: 3, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: liked ? 'Unlike' : 'Like', icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded), onPressed: _loading ? null : () => library.toggleFavorite(widget.item.song)),
                _loading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(icon: const Icon(Icons.play_arrow_rounded), onPressed: _play),
              ],
            ),
            onTap: _loading ? null : _play,
          ),
        );
      },
    );
  }
}

Widget _sectionTitle(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
);
