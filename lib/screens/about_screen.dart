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
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -12,
                  top: -18,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.14,
                      child: const ResonateLogo(size: 190, full: true, showWord: false),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      'A local-first music player built around your own audio files: library browsing, dual-engine crossfade, '
                      'equalizer and audio automation, audio-reactive visuals, optional DJ Mode, and on-device recommendations. '
                      'Resonate does not require a streaming subscription to play your local music.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
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
              '• Open Settings → Scan & folders to grant media access, choose folders, and rescan.\n'
              '• Tap the search icon in the Library toolbar to search titles, artists, and albums without losing list space.\n'
              '• Tap a track to play it; long-press to queue it. The library restores the current track row when possible.\n'
              '• Use the toolbar menu to sort, filter, and find possible duplicates.\n\n'
              'Player & crossfade\n'
              '• Use the queue, seek bar, sleep timer, EQ, and transport controls from the player.\n'
              '• Settings → Crossfade controls the transition toggle, duration, and fade curve. Some listening modes intentionally block crossfade.\n'
              '• Repeat one can crossfade back into the same track when crossfade is enabled. Skip and pause should cancel a transition.\n\n'
              'Sound & visualization\n'
              '• Settings → Equalizer controls tone, preamp, bass, width, and reverb. Audio automation controls interruption behavior and EQ headroom.\n'
              '• Settings → Visualization & Orb shares audio-response settings between the main visualizer and Ask Resonate. Spectrum capture is optional and may be unavailable on some devices.\n\n'
              'Ask Resonate & Intelligence\n'
              '• Use the orb quick actions to explore similar tracks, change energy, or refine recommendations; there is no free-text prompt box.\n'
              '• Intelligence recommendations and feedback are local. Autopilot requires explicit consent before it can change or enqueue tracks.\n\n'
              'DJ Mode & listening modes\n'
              '• DJ Mode is optional and can use offline analysis for beat-aware handoffs and light transition effects. Missing analysis must not block normal playback.\n'
              '• Driving, Podcast, Audiobook, and other modes can apply different folder, playback, and crossfade policies. Check the active mode if a control is unavailable.\n\n'
              'Bluetooth & automation\n'
              '• Settings → Audio automation controls interruption response; Device controls covers media buttons and connection behavior.\n'
              '• Output changes are handled automatically where Android exposes enough information. Device and route behavior varies by manufacturer.',
            ),
          ),

          _tile(
            context,
            icon: Icons.auto_awesome_outlined,
            title: 'What is included',
            child: const Text(
              'Playback\n'
              '• Dual-engine A/B crossfade with configurable duration and curve; gapless playback when crossfade is off.\n'
              '• Queue, shuffle/repeat, per-track resume, and sleep timer with fade-out.\n'
              '• Route-change recovery and guarded playback transitions.\n\n'
              'Sound & visuals\n'
              '• Multi-band equalizer, preamp, bass, width, and reverb controls.\n'
              '• Shared audio-reactive spectrum for the main visualizer and Ask Resonate orb, with sensitivity and performance controls.\n'
              '• Audio automation for interruption policy and EQ headroom.\n\n'
              'DJ Mode (optional)\n'
              '• Offline analysis can inform tempo, energy, structure hints, and harmonic transitions.\n'
              '• Transition strategies include beat/phrase alignment, outro-to-intro, energy bridges, and light transition effects.\n'
              '• Weighted skip feedback helps recommendations avoid repeatedly suggesting tracks you skip early.\n\n'
              'Intelligence & privacy\n'
              '• Local ranking uses listening feedback such as completions, skips, and seeks.\n'
              '• Autopilot has graduated consent controls; automatic queue/play changes require permission.\n'
              '• History, preferences, and analysis are intended to remain on-device; exports contain settings, not audio files.',
            ),
          ),

          _tile(
            context,
            icon: Icons.gavel_outlined,
            title: 'License',
            child: const Text(
              'Resonate original application code, branding, and bundled assets are covered by the Resonate Restricted Use License in the project root.\n\n'
              'You may use and privately modify a copy for personal, non-commercial purposes. You may not redistribute the app or modified copies, sell or commercially exploit it, sublicense it, or use the Resonate name/logo to imply endorsement without written permission.\n\n'
              'Third-party packages and assets remain under their own licenses. This short summary is informational; the full license text in the repository controls.',
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
              applicationLegalese: 'Copyright © 2026 Aetherion · Resonate by innotrepid',
            ),
          ),

          const SizedBox(height: 16),
          Text(
            'Copyright © 2026 Aetherion · Resonate by innotrepid',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'All rights reserved. Third-party components retain their own license terms. '
            'Resonate is not affiliated with a streaming service; it plays compatible audio files available to your device.',
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
