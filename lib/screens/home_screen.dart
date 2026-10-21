import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/ask_resonate/ask_resonate_controller.dart';
import '../widgets/ask_resonate/ask_resonate_orb.dart';
import '../widgets/ask_resonate/ask_resonate_overlay.dart';
import '../widgets/mini_player_bar.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import '../navigation/shell_nav.dart';
import 'home_dashboard.dart';

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
    HomeDashboard(),
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
    if (index == 3) context.read<AskResonateController>().close();
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
              onPageChanged: (index) {
                if (index == 3) context.read<AskResonateController>().close();
                setState(() {
                _selectedIndex = index;
                _navigationVisible = true;
                });
              },
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
