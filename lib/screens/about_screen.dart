import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About Resonate')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHighest]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Resonate', style: theme.textTheme.displaySmall?.copyWith(fontFamily: 'serif', fontStyle: FontStyle.italic, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('0.1.0 • Local-first intelligent music player', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 18),
              Text('Resonate is an offline-first music player built around a simple idea: your local library should remain yours while the player becomes more useful the more you listen.', style: theme.textTheme.bodyLarge),
            ]),
          ),
          const SizedBox(height: 28),
          _section(context, 'What is Resonate?', 'Resonate combines local music discovery, reliable playback, audio controls, Bluetooth/media controls and a privacy-first Intelligence layer. The Intelligence system is designed to learn from local listening behavior rather than requiring a cloud recommendation profile.'),
          _section(context, 'How to use Resonate', '1. Give Resonate audio access when Android asks.\n\n2. Open Settings → Library to manage music folders and scanning.\n\n3. Open Library, choose a song and tap it to play. Use the Player for seeking, volume and playback controls.\n\n4. Open Settings → Audio for the main equalizer, per-song EQ and effects. Crossfade is under Settings → Playback → Crossfade.\n\n5. Open Settings → Intelligence → Master switch & Authority. Suggestions keep control manual; Assist and Autopilot progressively allow Intelligence to help with what comes next.\n\n6. Connect Bluetooth devices through Android. Resonate handles media buttons and the configured connection behavior.\n\n7. Keep listening. When Intelligence is enabled, finishes, skips, transitions and feedback become local signals used to improve recommendations.'),
          _section(context, 'Intelligence explained', 'Resonate Intelligence starts as a local recommendation companion. It scores songs using listening history, transitions, completion behavior, artist affinity, time patterns, feedback and freshness. Recommendations include an explanation and confidence. After enough local evidence has accumulated, Intelligence can graduate to Autopilot and automatically prepare the next part of a session. You can turn Intelligence off at any time and return to manual playback.'),
          _section(context, 'Implemented', 'Playback with background audio and media notifications\n\n• Android foreground playback notification\n• Bluetooth/media-button command routing\n• Queue and next/previous playback\n• Crossfade controls\n• Main equalizer and audio effects\n• Per-song EQ entry point\n• Local music library and folder management\n• Listening-event storage for Intelligence\n• Explainable local recommendations\n• Intelligence enable/disable control\n• Suggest / Assist / Autopilot authority levels\n• Automatic Autopilot graduation after sufficient learning\n• Session-aware Autopilot queue selection\n• Theme controls\n• Companion-style Settings organization\n• Local-first privacy model\n• MIT license'),
          _section(context, 'In progress', '• Deeper Intelligence session learning and feedback loops\n• Stronger automatic sequencing and exploration decisions\n• Long-mix analysis and detection of the sections a listener repeatedly enjoys\n• More complete per-song EQ behavior under Intelligence\n• Dedicated sub-settings pages for major Settings categories\n• More advanced library scanning and folder handling\n• Intelligence data export and broader privacy controls\n• Additional Bluetooth/device refinements\n• Broader playback behavior refinements as device testing continues'),
          _section(context, 'Testing status', 'The latest Android APK has been tested successfully on Android 13 with playback, notifications, background playback and continued playback after leaving the app. Older Android versions remain part of ongoing compatibility testing.'),
          _section(context, 'Privacy', 'Resonate is designed around local-first operation. Listening signals used by Intelligence are stored and processed on the device. The current design does not require a remote recommendation profile.'),
          _section(context, 'Open-source license', 'Resonate is distributed under the MIT License. The complete license text is included in the project LICENSE file.'),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 18),
          Center(child: Text('Copyright © 2026 Aetherion', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Center(child: Text('Resonate • Built for local music, thoughtful playback and private intelligence.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 9),
      Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ]),
  );
}
