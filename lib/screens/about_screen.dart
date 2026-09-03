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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Resonate', style: theme.textTheme.displaySmall?.copyWith(fontFamily: 'serif', fontStyle: FontStyle.italic, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('0.1.0 • Local-first intelligent music player', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 18),
              Text('Your library stays on your device. Resonate combines local playback, audio controls and Intelligence that learns from the way you listen.', style: theme.textTheme.bodyLarge),
            ]),
          ),
          const SizedBox(height: 28),
          Text('How to use Resonate', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 14),
          _Step(number: '1', title: 'Give Resonate music access', text: 'Allow audio access when Android asks. This lets Resonate discover your local audio library.'),
          _Step(number: '2', title: 'Choose your folders', text: 'Open Settings → Library → Folders and select the folders that contain your music. Resonate scans the selected folder immediately after you choose it.'),
          _Step(number: '3', title: 'Start listening', text: 'Open Library, choose a song and tap it to play. The Player gives you playback controls, seeking, volume and your existing audio features.'),
          _Step(number: '4', title: 'Shape your sound', text: 'Use Settings → Audio for the main equalizer, per-song EQ and audio effects. Crossfade is available under Settings → Playback → Crossfade.'),
          _Step(number: '5', title: 'Use Intelligence when you want it', text: 'Open Settings → Intelligence → Master switch & Authority. Suggestions let Resonate recommend; Autopilot can prepare high-confidence next tracks. You can turn Intelligence off at any time.'),
          _Step(number: '6', title: 'Use Bluetooth controls', text: 'Connect your Bluetooth audio device normally through Android. Resonate handles media-button commands and the playback behavior you choose under Settings → Bluetooth & Devices.'),
          _Step(number: '7', title: 'Let it learn', text: 'With Intelligence enabled, finishes, skips and song-to-song choices become local signals. Recommendations include a reason and confidence so you can understand the decision.'),
          const SizedBox(height: 18),
          Text('Privacy', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Resonate Intelligence is designed to learn locally on the device. Your listening behavior is used to improve local recommendations rather than requiring a cloud recommendation profile.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 18),
          Center(child: Text('Copyright © 2026 Aetherion', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Center(child: Text('All rights reserved.', style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final String text;
  const _Step({required this.number, required this.title, required this.text});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle), child: Text(number, style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: theme.textTheme.titleMedium), const SizedBox(height: 4), Text(text, style: theme.textTheme.bodyMedium)])),
      ]),
    );
  }
}
