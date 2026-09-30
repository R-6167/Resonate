import 'package:flutter/material.dart';
import '../ui/resonate_glass.dart';

import '../widgets/resonate_logo.dart';

/// Keep in sync with pubspec.yaml version when bumping releases.
const String kResonateVersion = '0.1.5';
const String kResonateBuild = '6';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final versionLabel = '$kResonateVersion+$kResonateBuild';

    return ResonateGlassScaffold(
      title: const Text('About Resonate'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ResonateLogo(size: 72, full: true, showWord: false),
                const SizedBox(height: 14),
                Text(
                  'Resonate',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontStyle: FontStyle.italic,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Version $versionLabel',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your music. Your rules. Fully offline.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'A local-first companion player: library, intelligent mixes, optional DJ Mode, '
                  'and on-device learning. Audio and listening evidence stay on this device.',
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _tile(
            context,
            icon: Icons.menu_book_outlined,
            title: 'How to use',
            child: const Text(
              'Library\n'
              '• Settings → Library: grant access, pick folders, scan, set a minimum length.\n'
              '• Tap a song to play; long-press to queue as next.\n\n'
              'Player\n'
              '• Seek, volume, sleep timer, EQ, effects, and crossfade from More or Settings.\n'
              '• Swipe artwork: left = next, right = previous.\n\n'
              'Intelligence\n'
              '• Turn on for local recommendations and automatic mixes.\n'
              '• Ask Resonate (floating action): more like this, calmer energy, explore, avoid artist, and more.\n\n'
              'DJ Mode\n'
              '• Optional. When on, Resonate plans beat-aware handoffs, harmonic leans, and light transition FX.\n'
              '• Normal playback always works if analysis is missing — DJ never blocks audio.\n\n'
              'Autopilot\n'
              '• Choose the mode under Intelligence settings.\n'
              '• Explicit consent is required before Autopilot can change or enqueue tracks.\n\n'
              'Bluetooth\n'
              '• Media buttons plus optional pause/resume on connect or disconnect.\n'
              '• Route changes are recovered automatically when you switch outputs.',
            ),
          ),

          _tile(
            context,
            icon: Icons.auto_awesome_outlined,
            title: 'What is included',
            child: const Text(
              'Playback\n'
              '• Dual-engine A/B crossfade with smooth volume ramps; gapless when crossfade is off.\n'
              '• Queue, shuffle/repeat, per-song resume, sleep timer with fade-out.\n'
              '• Bluetooth route recovery and volume unstick after device switches.\n\n'
              'Sound\n'
              '• Multi-band equalizer, soft preamp, device-aware EQ profiles.\n'
              '• Effects (bass boost, virtualizer, reverb, loudness) with light guidance.\n'
              '• Optional visualization.\n\n'
              'DJ Mode (optional)\n'
              '• Offline PCM analysis for tempo, energy, structure hints, and key lean.\n'
              '• Transition strategies: beat align, phrase align, outro→intro, energy bridge.\n'
              '• Camelot-style harmonic bias with Intelligence ranking when DJ is on.\n'
              '• Random transition SFX rack beyond reverb; EQ filter sweeps on handoff.\n'
              '• Weighted skip feedback so early skips teach the planner what not to repeat.\n\n'
              'Intelligence\n'
              '• Local ranking from completions, skips, seeks, and mix journeys.\n'
              '• Decision log and rule-based Ask Resonate.\n'
              '• Autopilot with graduated consent.\n\n'
              'Privacy\n'
              '• History, preferences, analysis, and decisions stay on-device.\n'
              '• Transfer exports settings only — never your audio files.',
            ),
          ),

          _tile(
            context,
            icon: Icons.gavel_outlined,
            title: 'License',
            child: const Text(
              'Resonate application code is provided under the terms distributed with this project source.\n\n'
              'Open-source packages (Flutter, just_audio, and others) remain under their own licenses. '
              'Open the licenses page below to review them on device.',
            ),
          ),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.policy_outlined, color: scheme.primary),
            title: const Text('Open-source licenses'),
            subtitle: const Text('Flutter and third-party package licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Resonate',
              applicationVersion: versionLabel,
              applicationLegalese: 'Copyright © innotrepid',
            ),
          ),

          const SizedBox(height: 16),
          Text(
            'Copyright © innotrepid',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'All rights reserved unless otherwise stated in the project license. '
            'Resonate is not affiliated with any streaming service; it plays files from your device.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return ResonateGlassCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(alignment: Alignment.centerLeft, child: child),
        ],
      ),
    );
  }
}
