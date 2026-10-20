import 'package:flutter/material.dart';
import '../ui/resonate_glass.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import '../providers/intelligence_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../providers/listening_history_provider.dart';
import '../services/playback_authority.dart';
import '../widgets/dj_mode_status_chip.dart';
import '../widgets/evolving_mix_card.dart';
import '../widgets/autopilot_home_card.dart';
import '../widgets/ask_resonate_sheet.dart';
import '../widgets/ask_resonate/ask_resonate_controller.dart';
import '../widgets/ask_resonate/ask_resonate_orb.dart';
import '../widgets/ask_resonate/ask_resonate_overlay.dart';
import '../widgets/resonate_logo.dart';
import '../widgets/resonate_mode_chip.dart';
import '../widgets/mode_player_density.dart';
import '../modes/providers/mode_provider.dart';
import '../widgets/mode_shelf_card.dart';
import '../widgets/driving_suggestion_banner.dart';
import '../widgets/mini_player_bar.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import '../navigation/shell_nav.dart';

String _homeFormatClock(int ms) {
  final totalSec = (ms / 1000).floor().clamp(0, 24 * 3600);
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _homeFormatHours(int ms) {
  final minutes = Duration(milliseconds: ms).inMinutes;
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _navigationVisible = true;
  late final PageController _pageController;
  ShellNav? _shellNav;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shellNav = context.read<ShellNav>();
      _shellNav?.bind(_selectPage);
    });
  }

  @override
  void dispose() {
    _shellNav?.unbind();
    _pageController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
      _navigationVisible = true;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleScroll(ScrollNotification notification) {
    if (notification.depth > 1 || notification.metrics.axis != Axis.vertical) return;

    final delta = notification is ScrollUpdateNotification
        ? notification.scrollDelta
        : notification is OverscrollNotification
            ? notification.overscroll
            : null;
    if (delta == null || delta.abs() < 2) return;

    final shouldShow = delta < 0;
    if (shouldShow != _navigationVisible && mounted) {
      setState(() => _navigationVisible = shouldShow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showAsk = _selectedIndex <= 2;

    final labels = const ['For You', 'Library', 'Player', 'Settings'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AskResonateController>().setContext(labels[_selectedIndex.clamp(0, 3)]);
    });

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _handleScroll(notification);
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: _screens.length,
              onPageChanged: (index) => setState(() {
                _selectedIndex = index;
                _navigationVisible = true;
              }),
              itemBuilder: (_, index) => _screens[index],
            ),
          ),
          if (showAsk) const AskResonateOrb(),
          if (context.watch<AskResonateController>().isOpen)
            const AskResonateOverlay(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedIndex != 2)
            MiniPlayerBar(onOpenPlayer: () => _selectPage(2)),
          ClipRect(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: _navigationVisible ? 80 : 20,
              child: _navigationVisible
                  ? NavigationBar(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectPage,
                      destinations: const [
                        NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'For You'),
                        NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
                        NavigationDestination(icon: Icon(Icons.music_note_outlined), selectedIcon: Icon(Icons.music_note), label: 'Player'),
                        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
                      ],
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _navigationVisible = true),
                      onVerticalDragUpdate: (details) {
                        if (details.delta.dy > 1) {
                          setState(() => _navigationVisible = true);
                        }
                      },
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
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
    final music = context.read<MusicProvider>();
    final currentSong = context.select<MusicProvider, Song?>((p) => p.currentSong);
    final isPlaying = context.select<MusicProvider, bool>((p) => p.isPlaying);
    final canContinueListening = context.select<MusicProvider, bool>((p) => p.canContinueListening);
    final resumePositionMs = context.select<MusicProvider, int>((p) => p.resumePositionMs);
    final currentDuration = context.select<MusicProvider, Duration?>((p) => p.currentDuration);
    final intelligence = context.watch<IntelligenceProvider>();
    final modes = context.watch<ModeProvider>();
    final density = ModePlayerDensity.fromMode(modes);
    final songs = library.allSongs;
    final recommendationQueue = intelligence.recommendations.map((item) => item.song).toList();
    final children = <Widget>[
      const SizedBox(height: 6),
      AutopilotHomeCard(songCount: songs.length),
    ];

    if (canContinueListening && currentSong != null && !isPlaying) {
      final song = currentSong;
      final pos = resumePositionMs;
      final dur = (currentDuration ?? song.duration).inMilliseconds;
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

    final history = context.watch<ListeningHistoryProvider>();
    final recentSongs = <Song>[];
    final seen = <String>{};
    for (final item in history.items) {
      final s = item.song;
      if (s == null || seen.contains(s.id)) continue;
      seen.add(s.id);
      recentSongs.add(s);
      if (recentSongs.length >= 12) break;
    }
    if (recentSongs.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 16),
        _sectionTitle(context, 'Recently played'),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recentSongs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final song = recentSongs[i];
              return SizedBox(
                width: 200,
                child: ResonateGlassCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    leading: const CircleAvatar(
                      child: Icon(Icons.history_rounded, size: 18),
                    ),
                    title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      await music.playSong(song);
                      if (context.mounted) openShellPlayer(context);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ]);
    }

    if (intelligence.isEnabled) {
      children.addAll([
        const SizedBox(height: 16),
        const DrivingSuggestionBanner(),
        const ModeShelfCard(),
        const EvolvingMixCard(),
      ]);
    }

    if (currentSong != null) {
      children.addAll([
        const SizedBox(height: 20),
        _sectionTitle(context, 'Now playing'),
        ResonateGlassCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: CircleAvatar(child: Icon(isPlaying ? Icons.graphic_eq : Icons.pause_rounded)),
            title: Text(currentSong.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(currentSong.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                const DjModeStatusChip(dense: true),
              ],
            ),
            trailing: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                minimumSize: Size(density.homePlayMinWidth, density.homePlayMinHeight),
                padding: EdgeInsets.symmetric(
                  horizontal: density.largeControls ? 18 : 12,
                  vertical: density.largeControls ? 12 : 8,
                ),
              ),
              onPressed: () => PlaybackAuthority.instance.userToggle(music),
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: density.largeControls ? 28 : 22),
              label: Text(isPlaying ? 'Pause' : 'Play'),
            ),
            onTap: () => openShellPlayer(context),
          ),
        ),
      ]);
    }

    children.addAll([
      const SizedBox(height: 20),
      _sectionTitle(context, intelligence.isEnabled ? 'More music for this moment' : 'Suggested from your library'),
      ..._recommendations(intelligence, recommendationQueue.isEmpty ? songs : recommendationQueue),
      const SizedBox(height: 30),
    ]);

    return ResonateGlassScaffold(
      title: const ResonateLogo(size: 48),
      actions: const [ResonateModeChip(dense: true)],
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

class _SessionCard extends StatelessWidget {
  final IntelligenceProvider intelligence;
  const _SessionCard({required this.intelligence});

  @override
  Widget build(BuildContext context) {
    return ResonateGlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your listening flow', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const SizedBox(width: 42, height: 24, child: _LearningWaveDots()),
            const SizedBox(width: 10),
            Expanded(child: Text(intelligence.sessionSummary)),
          ]),
          if (intelligence.sessionArtists.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Current flow: ${intelligence.sessionArtists.take(3).join(' • ')}'),
          ],
        ]),
      ),
    );
  }
}

class _LearningWaveDots extends StatefulWidget {
  const _LearningWaveDots();
  @override
  State<_LearningWaveDots> createState() => _LearningWaveDotsState();
}

class _LearningWaveDotsState extends State<_LearningWaveDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (index) {
            final phase = (_controller.value + index * .18) % 1.0;
            final wave = (0.5 + 0.5 * mathSin(phase * 6.283185307)).clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(0, -6 * wave),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
              ),
            );
          }),
        ),
      );
}

double mathSin(double value) {
  var x = value;
  while (x > 3.1415926535) x -= 6.283185307;
  while (x < -3.1415926535) x += 6.283185307;
  final x2 = x * x;
  return x * (1 - x2 / 6 + (x2 * x2) / 120 - (x2 * x2 * x2) / 5040);
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
      final list = widget.songs.whereType<Song>().toList();
      final q = index >= 0 && index < list.length ? list.sublist(index) : <Song>[widget.item.song];
      await music.playSong(widget.item.song, queue: q, startIndex: 0);
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
        final confidenceText = '${widget.item.confidenceLabel} • $confidence%';
        return ResonateGlassCard(
          blurEnabled: false,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.only(bottom: 9),
          child: ListTile(
            leading: CircleAvatar(
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.music_note_rounded),
            ),
            title: Text(widget.item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${widget.item.song.artist}\n$confidenceText · ${widget.item.reason}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: liked ? 'Unlike' : 'Like',
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
              onPressed: () => library.toggleFavorite(widget.item.song),
            ),
            onTap: _play,
          ),
        );
      },
    );
  }
}
