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
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
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
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'For You',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.music_note_outlined),
            selectedIcon: Icon(Icons.music_note),
            label: 'Player',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard();

  List<Widget> _recommendations(
    IntelligenceProvider intelligence,
    List<dynamic> songs,
  ) {
    if (!intelligence.isEnabled) {
      return const [
        Card(
          child: ListTile(
            leading: Icon(Icons.auto_awesome_outlined),
            title: Text('Intelligence is off'),
            subtitle: Text(
              'Your player remains fully manual. Enable it from Settings when you want local anticipation.',
            ),
          ),
        ),
      ];
    }

    final recommendations = intelligence.recommendations.skip(1).toList();
    if (recommendations.isEmpty) {
      return const [
        Card(
          child: ListTile(
            leading: Icon(Icons.headphones_rounded),
            title: Text('Let Resonate get to know your taste'),
            subtitle: Text(
              'Finishes, skips and song-to-song choices become local signals for future decisions.',
            ),
          ),
        ),
      ];
    }

    return recommendations
        .map<Widget>(
          (item) => _RecommendationTile(item: item, songs: songs),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final music = context.watch<MusicProvider>();
    final intelligence = context.watch<IntelligenceProvider>();
    final songs = library.allSongs;
    final recommendationQueue =
        intelligence.recommendations.map((item) => item.song).toList();
    final next = intelligence.anticipatedNext;
    final children = <Widget>[
      const SizedBox(height: 8),
      Text(
        'Welcome back.',
        style: Theme.of(context)
            .textTheme
            .displaySmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        'Something good is waiting in your library.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 18),
      _IntelligenceHero(
        intelligence: intelligence,
        songCount: songs.length,
      ),
    ];

    if (intelligence.isEnabled) {
      children.addAll([
        const SizedBox(height: 16),
        _SessionCard(intelligence: intelligence),
        const SizedBox(height: 14),
        const EvolvingMixCard(),
      ]);
    }

    if (music.currentSong != null) {
      children.addAll([
        const SizedBox(height: 20),
        _sectionTitle(context, 'Now playing'),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(
                music.isPlaying
                    ? Icons.graphic_eq
                    : Icons.pause_rounded,
              ),
            ),
            title: Text(
              music.currentSong!.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              music.currentSong!.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: FilledButton.tonalIcon(
              onPressed: () =>
                  PlaybackAuthority.instance.userToggle(music),
              icon: Icon(
                music.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              label: Text(music.isPlaying ? 'Pause' : 'Play'),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PlayerScreen(),
                ),
              );
            },
          ),
        ),
      ]);
    }

    if (intelligence.isEnabled && next != null) {
      children.addAll([
        const SizedBox(height: 20),
        _sectionTitle(
          context,
          intelligence.isAutopilot
              ? 'Next up, intelligently'
              : 'A little nudge',
        ),
        _AnticipationCard(
          item: next,
          songs: recommendationQueue.isEmpty
              ? songs
              : recommendationQueue,
        ),
      ]);
    }

    children.addAll([
      const SizedBox(height: 20),
      _sectionTitle(
        context,
        intelligence.isEnabled
            ? 'More music for this moment'
            : 'Suggested from your library',
      ),
      ..._recommendations(
        intelligence,
        recommendationQueue.isEmpty ? songs : recommendationQueue,
      ),
      const SizedBox(height: 30),
    ]);

    return Scaffold(
      appBar: AppBar(title: const Text('Resonate')),
      body: RefreshIndicator(
        onRefresh: intelligence.refreshRecommendations,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 34),
          children: children,
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _IntelligenceHero extends StatelessWidget {
  final IntelligenceProvider intelligence;
  final int songCount;

  const _IntelligenceHero({
    required this.intelligence,
    required this.songCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = intelligence.isAutopilot
        ? 'You can just listen.'
        : intelligence.isAutopilotGraduated
            ? 'Resonate has your rhythm.'
            : 'Let Resonate learn your rhythm.';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            bottom: 4,
            child: IgnorePointer(
              child: Opacity(
                opacity: .11,
                child: Text(
                  'RESONATE',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 520),
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween(begin: .88, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  intelligence.isAutopilot
                      ? Icons.smart_toy_rounded
                      : Icons.auto_awesome,
                  key: ValueKey(intelligence.autonomyLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Resonate Intelligence',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                intelligence.isEnabled
                    ? intelligence.autonomyLabel
                    : 'OFF',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            intelligence.isEnabled ? title : 'Your player is fully manual.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 7),
          Text(
            intelligence.isEnabled
                ? 'Your listening patterns stay on this device and gradually shape what appears next.'
                : 'Intelligence is disabled. Nothing will predict or alter your playback.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              const Chip(label: Text('Local-first')),
              const Chip(label: Text('Explainable')),
              Chip(label: Text('$songCount songs')),
            ],
          ),
            ],
          ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your listening flow',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(intelligence.sessionSummary),
            if (intelligence.sessionArtists.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Current flow: ${intelligence.sessionArtists.take(3).join(' • ')}',
              ),
            ],
          ],
        ),
      ),
    );
  }
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
    final index = widget.songs.indexWhere(
      (song) => song.id == widget.item.song.id,
    );

    try {
      await music.playSong(
        widget.item.song,
        queue: index >= 0 ? widget.songs.cast() : [widget.item.song],
        startIndex: index >= 0 ? index : 0,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confidence =
        (widget.item.confidence.clamp(0.0, 1.0) * 100).round();

    return Card(
      child: ListTile(
        leading: const Icon(Icons.auto_awesome),
        title: Text(
          widget.item.song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$confidence% confidence • ${widget.item.reason}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: _play,
              ),
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
    final index = widget.songs.indexWhere(
      (song) => song.id == widget.item.song.id,
    );

    try {
      await music.playSong(
        widget.item.song,
        queue: index >= 0 ? widget.songs.cast() : [widget.item.song],
        startIndex: index >= 0 ? index : 0,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, library, _) {
        final liked = library.isFavoriteSync(widget.item.song.id);
        final confidence =
            (widget.item.confidence.clamp(0.0, 1.0) * 100).round();
        final confidenceText =
            '${widget.item.confidenceLabel} • $confidence%';

        return Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.music_note_rounded),
            ),
            title: Text(
              widget.item.song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${widget.item.song.artist}\n$confidenceText • ${widget.item.reason}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: liked ? 'Unlike' : 'Like',
                  icon: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                  onPressed: _loading
                      ? null
                      : () => library.toggleFavorite(widget.item.song),
                ),
                _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.play_arrow_rounded),
                        onPressed: _play,
                      ),
              ],
            ),
            onTap: _loading ? null : _play,
          ),
        );
      },
    );
  }
}
