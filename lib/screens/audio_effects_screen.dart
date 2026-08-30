import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_effects_provider.dart';

class AudioEffectsScreen extends StatelessWidget {
  const AudioEffectsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Effects'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
            onPressed: () {
              final effects =
                  context.read<AudioEffectsProvider>();

              effects.setReverb(0.0);
              effects.setBassBoost(0.0);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Audio effects reset to default'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<AudioEffectsProvider>(
        builder: (context, effects, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio Effects',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),

                const SizedBox(height: 8),

                Text(
                  'Enhance your listening experience with audio effects.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),

                const SizedBox(height: 30),

                _EffectCard(
                  icon: Icons.surround_sound,
                  title: 'Reverb',
                  description:
                      'Add space and depth to the sound.',
                  value: effects.reverb,
                  onChanged: effects.setReverb,
                ),

                const SizedBox(height: 20),

                _EffectCard(
                  icon: Icons.graphic_eq,
                  title: 'Bass Boost',
                  description:
                      'Increase the low-frequency bass response.',
                  value: effects.bassBoost,
                  onChanged: effects.setBassBoost,
                ),

                const SizedBox(height: 30),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .primaryColor
                        .withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Adjust the sliders to control the intensity '
                          'of each effect. Your settings are saved '
                          'automatically.',
                          style:
                              Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          );
        },
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
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 30,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  '$percentage%',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                        color:
                            Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Slider(
              value: value.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              divisions: 20,
              label: '$percentage%',
              onChanged: onChanged,
            ),

            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Off'),
                  Text('Maximum'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
