import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/crossfade.dart';
import '../providers/crossfade_provider.dart';

class CrossfadeScreen extends StatelessWidget {
  const CrossfadeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crossfade'),
        actions: [
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: Consumer<CrossfadeProvider>(
        builder: (context, crossfade, _) {
          final enabled = crossfade.isEnabled;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Transition',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Blend the end of one track into the beginning of the next without interrupting playback.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding:
                          const EdgeInsets.fromLTRB(18, 8, 14, 8),
                      secondary: const Icon(Icons.multitrack_audio_rounded),
                      title: const Text(
                        'Crossfade',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        enabled
                            ? 'Dual-engine transitions are active'
                            : 'Tracks play normally',
                      ),
                      value: enabled,
                      onChanged: crossfade.toggleCrossfade,
                    ),
                    if (enabled) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Duration',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  crossfade.getDurationString(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Slider(
                              value: crossfade.duration
                                  .clamp(500.0, 12000.0)
                                  .toDouble(),
                              min: 500,
                              max: 12000,
                              divisions: 46,
                              label: crossfade.getDurationString(),
                              onChanged: crossfade.setDuration,
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('0.5 sec'),
                                  Text('6 sec'),
                                  Text('12 sec'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (enabled) ...[
                const SizedBox(height: 18),
                Text(
                  'Presets',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: CrossfadePresets.presets.entries
                          .where((entry) => entry.value > 0)
                          .map(
                            (entry) {
                              final selected =
                                  crossfade.duration == entry.value;
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  selected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  color: selected ? scheme.primary : null,
                                ),
                                title: Text(entry.key),
                                selected: selected,
                                onTap: () =>
                                    crossfade.applyPreset(entry.value),
                              );
                            },
                          )
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Fade curve',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: DropdownButtonFormField<String>(
                      initialValue: crossfade.fadeType,
                      decoration:
                          const InputDecoration(border: InputBorder.none),
                      items: const [
                        DropdownMenuItem(
                          value: 'linear',
                          child: Text('Linear'),
                        ),
                        DropdownMenuItem(
                          value: 'ease_in',
                          child: Text('Ease in'),
                        ),
                        DropdownMenuItem(
                          value: 'ease_out',
                          child: Text('Ease out'),
                        ),
                        DropdownMenuItem(
                          value: 'ease_in_out',
                          child: Text('Ease in & out'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          crossfade.setFadeType(value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.sync_alt_rounded),
                    title: Text('How Resonate does it'),
                    subtitle: Text(
                      'The inactive playback engine loads the next track, fades it in while the current engine fades out, then becomes the active engine. User commands can cancel a transition immediately.',
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset crossfade?'),
        content: const Text(
          'Crossfade will be turned off and the fade curve will return to Linear.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (reset == true && context.mounted) {
      await context.read<CrossfadeProvider>().reset();
    }
  }
}
