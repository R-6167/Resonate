#!/usr/bin/env python3
"""Adapt PlayerScreen to Mode PlaybackPolicy uiDensity."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "lib/screens/player_screen.dart"
t = path.read_text()

if "ModeProvider" in t and "uiDensity" in t:
    print("player: mode shells already present")
    raise SystemExit(0)

# Imports
if "mode_provider.dart" not in t:
    t = t.replace(
        "import '../providers/music_provider.dart';\n",
        "import '../providers/music_provider.dart';\n"
        "import '../providers/mode_provider.dart';\n"
        "import '../models/playback_policy.dart';\n"
        "import '../models/resonate_mode.dart';\n",
        1,
    )

# Replace build method header through actions to be mode-aware
old_scaffold_start = """  Widget build(BuildContext context) {
    return ResonateGlassScaffold(
      title: const Text('Now Playing'),
      actions: [
          const DjModeStatusChip(dense: true),
          Consumer<MusicProvider>(
            builder: (_, music, __) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Chip(
                    avatar: Icon(
                      music.activeEngineLabel == 'A'
                          ? Icons.looks_one_rounded
                          : Icons.looks_two_rounded,
                      size: 17,
                    ),
                    label: Text('Engine ${music.activeEngineLabel}'),
                  ),
                ),
              );
            },
          ),
        ],

      body: Consumer<MusicProvider>(
        builder: (context, music, _) {
          final song = music.currentSong;
"""

new_scaffold_start = """  Widget build(BuildContext context) {
    final modeProvider = context.watch<ModeProvider>();
    final density = modeProvider.policy.uiDensity;
    final mode = modeProvider.mode;
    final minimal = density == UiDensity.minimal;
    final reduced = density == UiDensity.reduced || minimal;
    final hideAdvanced = modeProvider.policy.hideAdvancedSettingsEntry || minimal;

    return ResonateGlassScaffold(
      title: Text(minimal ? '${mode.emoji} ${mode.label}' : 'Now Playing'),
      actions: [
          if (!minimal) const DjModeStatusChip(dense: true),
          // Compact mode chip always visible so density is obvious.
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Center(
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Text(mode.emoji, style: const TextStyle(fontSize: 14)),
                label: Text(mode.label),
                onPressed: () {
                  // Cycle is intentional for Driving/Running quick access later;
                  // for now open is not needed — chip is informational.
                },
              ),
            ),
          ),
          if (!reduced)
            Consumer<MusicProvider>(
              builder: (_, music, __) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Chip(
                      avatar: Icon(
                        music.activeEngineLabel == 'A'
                            ? Icons.looks_one_rounded
                            : Icons.looks_two_rounded,
                        size: 17,
                      ),
                      label: Text('Engine ${music.activeEngineLabel}'),
                    ),
                  ),
                );
              },
            ),
        ],

      body: Consumer<MusicProvider>(
        builder: (context, music, _) {
          final song = music.currentSong;
"""

if old_scaffold_start not in t:
    raise SystemExit("player: scaffold start miss")
t = t.replace(old_scaffold_start, new_scaffold_start, 1)
print("player: scaffold mode-aware")

# Art height
if "height: 250," in t:
    t = t.replace(
        "height: 250,",
        "height: minimal ? 160 : (reduced ? 200 : 250),",
        1,
    )
    print("player: art height by density")

# Secondary row: shuffle / repeat / queue / more — hide or simplify in minimal
# Find the secondary IconButton row block - wrap with if (!minimal)

# Intelligence cards: hide in minimal/reduced when hide advanced, or only minimal
old_intel = """              const SizedBox(height: 14),
              Consumer<IntelligenceProvider>(
                builder: (context, intelligence, _) {
                  final item = intelligence.anticipatedNext;
                  if (!intelligence.isEnabled || item == null) return const SizedBox.shrink();
                  return Column(
                    children: [
                      _NextCard(item: item, mode: intelligence.autonomyLabel),
                      const SizedBox(height: 10),
                      const AutopilotTakeoverCard(),
                    ],
                  );
                },
              ),
"""
new_intel = """              if (!minimal) ...[
                const SizedBox(height: 14),
                Consumer<IntelligenceProvider>(
                  builder: (context, intelligence, _) {
                    final item = intelligence.anticipatedNext;
                    if (!intelligence.isEnabled || item == null) return const SizedBox.shrink();
                    return Column(
                      children: [
                        if (!reduced)
                          _NextCard(item: item, mode: intelligence.autonomyLabel),
                        if (!reduced) const SizedBox(height: 10),
                        // Autopilot takeover stays in reduced (Running) so consent is reachable.
                        const AutopilotTakeoverCard(),
                      ],
                    );
                  },
                ),
              ],
"""
if old_intel in t:
    t = t.replace(old_intel, new_intel, 1)
    print("player: intelligence cards density-gated")
else:
    print("player: intel block miss")

# More options / queue / shuffle visibility in transport row
# Replace more options button to respect hideAdvanced
old_more = """                      IconButton(
                        tooltip: 'More options',
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: () => _showMoreOptions(context),
                      ),
"""
new_more = """                      if (!hideAdvanced)
                        IconButton(
                          tooltip: 'More options',
                          icon: const Icon(Icons.more_vert_rounded),
                          onPressed: () => _showMoreOptions(context),
                        ),
"""
if old_more in t:
    t = t.replace(old_more, new_more, 1)
    print("player: more options gated")

# Queue button: keep in reduced, hide in minimal
old_queue = """                      IconButton(
                        tooltip: 'Queue',
                        icon: const Icon(Icons.queue_music_rounded),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const QueueScreen(),
                            ),
                          );
                        },
                      ),
"""
new_queue = """                      if (!minimal)
                        IconButton(
                          tooltip: 'Queue',
                          icon: const Icon(Icons.queue_music_rounded),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const QueueScreen(),
                              ),
                            );
                          },
                        ),
"""
if old_queue in t:
    t = t.replace(old_queue, new_queue, 1)
    print("player: queue gated")

# Shuffle/repeat: hide in minimal
old_shuffle = """                      IconButton(
                        tooltip: 'Shuffle',
"""
# Find shuffle IconButton block - need careful match
# Use a simpler approach: wrap shuffle and repeat with if (!minimal)

# Transport play button size boost for minimal/reduced
if "Icons.play_arrow_rounded" in t or "Icons.pause_rounded" in t:
    # look for Icon size on main play
    pass

# Enlarge main transport for driving
# Common pattern: IconButton style: IconButton.styleFrom
if "PlaybackAuthority.instance.userToggle" in t:
    # Add padding around main controls when minimal - optional
    print("player: transport present")

# Soft note under title when not normal mode
# After song title area is complex - skip if hard

path.write_text(t)
print("player mode shells done")
