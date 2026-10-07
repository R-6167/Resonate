#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = ROOT / "lib/screens/crossfade_screen.dart"
t = p.read_text()

# Imports
if "mode_provider.dart" not in t:
    t = t.replace(
        "import '../providers/crossfade_provider.dart';\n",
        "import '../providers/crossfade_provider.dart';\n"
        "import '../providers/music_provider.dart';\n"
        "import '../modes/providers/mode_provider.dart';\n"
        "import '../modes/integration/resonate_mode_ports.dart';\n"
        "import '../modes/screens/modes_screen.dart';\n",
        1,
    )

# Switch body to Consumer2 or nested Consumer for Mode + Crossfade
if "Consumer2<CrossfadeProvider, ModeProvider>" not in t:
    t = t.replace(
        "      body: Consumer<CrossfadeProvider>(\n        builder: (context, crossfade, _) {\n          final enabled = crossfade.isEnabled;\n",
        "      body: Consumer2<CrossfadeProvider, ModeProvider>(\n        builder: (context, crossfade, modes, _) {\n          final enabled = crossfade.isEnabled;\n          final modeAllows = modes.crossfadeAllowed;\n          final music = context.watch<MusicProvider>();\n          final engineOn = music.effectiveCrossfadeEnabled;\n          final blockedByMode = enabled && !modeAllows;\n",
        1,
    )
    print("Consumer2")

# Banner after DjModeStatusBanner
marker = """              const DjModeStatusBanner(
                contextLabel:
                    'When DJ Mode is on, handoffs may seek to a beat and bias duration.',
              ),
              const SizedBox(height: 12),
"""
banner = """              const DjModeStatusBanner(
                contextLabel:
                    'When DJ Mode is on, handoffs may seek to a beat and bias duration.',
              ),
              if (blockedByMode) ...[
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: scheme.tertiaryContainer.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: scheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Blocked by ${modes.mode.label} mode',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Crossfade is on in settings, but ${modes.mode.label} '
                          'policy does not allow blending between tracks '
                          '(speech / chapter listening stays precise). '
                          'The engine will use hard cuts until you switch mode '
                          'or change policy.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onTertiaryContainer,
                              ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<
                                  void>(
                                builder: (_) => ModesScreen(
                                  folderPicker:
                                      const ResonateModeFolderPickerPort(),
                                ),
                              ),
                            );
                          },
                          child: const Text('Open Modes'),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (enabled && engineOn) ...[
                const SizedBox(height: 8),
                Text(
                  'Engine: crossfade active for this mode.',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ] else if (enabled && !engineOn) ...[
                const SizedBox(height: 8),
                Text(
                  'Engine: crossfade not applying (check duration and mode).',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.error,
                      ),
                ),
              ],
              const SizedBox(height: 12),
"""

if "Blocked by" not in t:
    if marker not in t:
        raise SystemExit("DjModeStatusBanner marker miss")
    t = t.replace(marker, banner, 1)
    print("banner inserted")
else:
    print("banner exists")

# Switch subtitle honesty
old_sub = """                  subtitle: Text(
                    enabled
                        ? 'Dual-engine transitions · ${crossfade.getDurationString()}'
                        : 'Tracks play end-to-end with a hard cut',
                  ),
"""
new_sub = """                  subtitle: Text(
                    blockedByMode
                        ? 'On in settings — blocked by ${modes.mode.label} mode'
                        : enabled
                            ? (engineOn
                                ? 'Dual-engine transitions · ${crossfade.getDurationString()}'
                                : 'Enabled — waiting for engine/duration')
                            : 'Tracks play end-to-end with a hard cut',
                  ),
"""
if old_sub in t:
    t = t.replace(old_sub, new_sub, 1)
    print("subtitle")
else:
    print("WARN subtitle")

p.write_text(t)
print("crossfade honesty done")

doc = ROOT / "docs/MODES.md"
if doc.exists():
    d = doc.read_text()
    d = d.replace(
        "- [ ] **Mode vs Crossfade UI honesty**",
        "- [x] **Mode vs Crossfade UI honesty**",
        1,
    )
    doc.write_text(d)
