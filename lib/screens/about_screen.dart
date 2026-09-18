import 'package:flutter/material.dart';

/// Keep in sync with pubspec.yaml version when bumping releases.
const String kResonateVersion = '0.1.3';
const String kResonateBuild = '4';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final versionLabel = '$kResonateVersion+$kResonateBuild';

    return Scaffold(
      appBar: AppBar(title: const Text('About Resonate')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
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
                Text(
                  'Resonate',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Version $versionLabel',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Local-first companion music player',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  'Offline library playback with a local companion for recommendations, mixes, Autopilot, and Ask Resonate. Your audio and listening evidence stay on this device.',
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
              '• Settings → Library: grant access, choose folders, scan, set minimum length.\n'
              '• Tap a song to play; long-press to queue as next.\n\n'
              'Player\n'
              '• Seek, volume, sleep timer, EQ and crossfade from More.\n'
              '• Swipe the artwork: left = next, right = previous.\n'
              '• Equalizer and Crossfade are in Settings anytime (no need to play first).\n\n'
              'For You\n'
              '• Enable Intelligence for recommendations and automatic mixes.\n'
              '• Ask Resonate (floating button): more like this, calmer mix, exploration, avoid artist, and more.\n\n'
              'Autopilot\n'
              '• Choose mode in Intelligence settings.\n'
              '• Consent is required before Autopilot can change or enqueue tracks.\n\n'
              'Bluetooth\n'
              '• Media buttons and optional resume/pause on connect or disconnect.\n'
              '• Device context (headphones / car / speaker) can nudge exploration.',
            ),
          ),

          _tile(
            context,
            icon: Icons.auto_awesome_outlined,
            title: 'What is included',
            child: const Text(
              'Playback: crossfade (A/B engines), gapless when crossfade is off, '
              'queue, shuffle/repeat, per-song resume, sleep timer with fade-out.\n\n'
              'Audio: multi-band equalizer, soft preamp, optional learned EQ leans, '
              'crossfade curves, effects, visualization.\n\n'
              'Companion: local ranking (transitions, completions, seek/replay), '
              'journey memory on mixes, decision log, rule-based Ask Resonate.\n\n'
              'Privacy: history, preferences, and decisions stay on-device. '
              'Transfer exports settings only, never audio files.',
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
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
