import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_effects_provider.dart';

class AudioEffectsScreen extends StatelessWidget {
  const AudioEffectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Effects'),
        actions: [
          Consumer<AudioEffectsProvider>(
            builder: (_, effects, __) => Switch(
              value: effects.effectsEnabled,
              onChanged: effects.setEffectsEnabled,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
            onPressed: () => context.read<AudioEffectsProvider>().reset(),
          ),
        ],
      ),
      body: Consumer<AudioEffectsProvider>(
        builder: (context, effects, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 32, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Resonate Sound Engine', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                            effects.effectsEnabled ? 'Live processing is active' : 'Audio processing is bypassed',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _EffectCard(
              icon: Icons.graphic_eq,
              title: 'Bass Boost',
              description: 'Add weight and punch to low frequencies.',
              value: effects.bassBoost,
              onChanged: effects.setBassBoost,
            ),
            _EffectCard(
              icon: Icons.surround_sound,
              title: 'Virtualizer',
              description: 'Widen the stereo image for headphones and speakers.',
              value: effects.virtualizer,
              onChanged: effects.setVirtualizer,
            ),
            _EffectCard(
              icon: Icons.water_drop_outlined,
              title: 'Reverb',
              description: 'Add controlled room ambience and depth.',
              value: effects.reverb,
              onChanged: effects.setReverb,
            ),
            _EffectCard(
              icon: Icons.volume_up_outlined,
              title: 'Loudness',
              description: 'Increase perceived loudness without changing the main volume control.',
              value: effects.loudness,
              onChanged: effects.setLoudness,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Tip: Start with Bass Boost around 20–35% and Virtualizer around 10–25%. Heavy processing can distort some tracks, so use the master volume and Preamp carefully.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EffectCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final double value;
  final ValueChanged<double> onChanged;

  const _EffectCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (value * 100).round();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(description, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text('$percentage%', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 12),
            Slider(
              value: value.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              divisions: 20,
              label: '$percentage%',
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
