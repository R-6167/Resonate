import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/crossfade_provider.dart';
import '../models/crossfade.dart';

class CrossfadeScreen extends StatelessWidget {
  const CrossfadeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crossfade'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset to Default?'),
                  content: const Text('This will reset crossfade to default settings.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        context.read<CrossfadeProvider>().reset();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Crossfade reset to default')),
                        );
                      },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<CrossfadeProvider>(
        builder: (context, crossfadeProvider, _) {
          return SingleChildScrollView(
            child: Column(
              children: [
                // Enable/Disable Toggle
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crossfade',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'Smooth transitions between songs',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      Switch(
                        value: crossfadeProvider.isEnabled,
                        onChanged: (value) {
                          crossfadeProvider.toggleCrossfade(value);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Status Display
                if (crossfadeProvider.isEnabled)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).primaryColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Crossfade Enabled',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: Theme.of(context).primaryColor,
                                    ),
                              ),
                              Text(
                                'Duration: ${crossfadeProvider.getDurationString()}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                // Duration Control
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⏱️ Duration',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Slider(
                        value: crossfadeProvider.duration,
                        min: 0,
                        max: 5000,
                        divisions: 50,
                        label: crossfadeProvider.getDurationString(),
                        onChanged: (value) {
                          crossfadeProvider.setDuration(value);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Off'),
                            Text(
                              crossfadeProvider.getDurationString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: Theme.of(context).primaryColor,
                                  ),
                            ),
                            const Text('5s'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Presets
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚡ Quick Presets',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: CrossfadePresets.presets.entries
                            .map(
                              (entry) => GestureDetector(
                                onTap: () {
                                  crossfadeProvider.applyPreset(entry.value);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Crossfade set to ${entry.key}'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: crossfadeProvider.duration ==
                                            entry.value
                                        ? Theme.of(context).primaryColor
                                        : Theme.of(context)
                                            .primaryColor
                                            .withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: crossfadeProvider.duration ==
                                              entry.value
                                          ? Theme.of(context).primaryColor
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      color: crossfadeProvider.duration ==
                                              entry.value
                                          ? Colors.white
                                          : Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Fade Type
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📈 Fade Curve',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context)
                                .primaryColor
                                .withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<String>(
                          value: crossfadeProvider.fadeType,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(
                              value: 'linear',
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('Linear'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'ease_in',
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('Ease In (gradual start)'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'ease_out',
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('Ease Out (gradual end)'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'ease_in_out',
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('Ease In Out (smooth both ends)'),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              crossfadeProvider.setFadeType(value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Info Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ℹ️ How Crossfade Works',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Crossfade gradually reduces the volume of the current song while increasing the volume of the next song\n'
                          '• Duration: How long the fade should take (0.5s - 5s)\n'
                          '• Fade Curve: How the volume changes:\n'
                          '  - Linear: Constant speed\n'
                          '  - Ease In: Slow start, then faster\n'
                          '  - Ease Out: Fast start, then slower\n'
                          '  - Ease In Out: Slow start and end\n'
                          '• Creates smooth, professional transitions between tracks',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}
