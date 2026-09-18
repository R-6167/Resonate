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
                  'Remake • Local-first companion player',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                Text(
                  'Resonate keeps your library offline while a local companion learns from listening on this device — recommendations, mixes, Autopilot, and Ask Resonate — without a cloud profile.',
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _section(
            context,
            'Playback',
            'Engine A/B crossfade, gapless window when crossfade is off, per-song resume positions, queue, sleep timer with fade-out, swipe next/previous on the player artwork, and reliable next/previous transport.',
          ),
          _section(
            context,
            'Audio',
            'Studio multi-band equalizer with hardware mapping, soft preamp, optional learned EQ leans per song or artist, crossfade curves, loudness/effects, and visualization settings.',
          ),
          _section(
            context,
            'Intelligence & Companion',
            'Suggest / Assist / Autopilot modes with explicit consent before Autopilot can change tracks. Ranking uses transitions, completions, seek/replay evidence, and avoided artists. Automatic mixes store journey memory across editions. Ask Resonate is a floating control on For You, Library, and Player: rule-based commands (more like this, calmer mix, exploration, avoid artist) with a local decision log.',
          ),
          _section(
            context,
            'Bluetooth',
            'Media controls, resume/pause on connect or disconnect, and device context classification (headphones, car, speaker) to guide exploration bias when enabled.',
          ),
          _section(
            context,
            'Privacy',
            'Listening history, seek memory, mix metadata, and companion decisions stay on this device. Transfer exports settings only — never your audio files.',
          ),
          _section(
            context,
            'How to use',
            '1. Grant audio access and scan library folders in Settings.\n'
            '2. Play from Library; use Player for seek, volume, EQ, and swipe transport.\n'
            '3. Open Settings → Audio / Playback for equalizer and crossfade anytime (no need to play first).\n'
            '4. Enable Intelligence for For You recommendations and mixes.\n'
            '5. Use Ask Resonate for quick companion commands.\n'
            '6. Grant Autopilot consent only when you want the app to enqueue or advance tracks.',
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
