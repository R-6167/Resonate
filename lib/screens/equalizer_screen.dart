import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/equalizer_provider.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  String _category = 'Genre';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          IconButton(
            tooltip: 'Save as preset',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => _saveCustom(context),
          ),
          IconButton(
            tooltip: 'Reset flat',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => context.read<EqualizerProvider>().resetToFlat(),
          ),
        ],
      ),
      body: Consumer<EqualizerProvider>(
        builder: (context, eq, _) {
          if (!eq.isAvailable) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Hardware equalizer is not available on this device. '
                  'Resonate uses Android’s system EQ bands when the DSP exposes them.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final categories = eq.categories;
          if (!categories.contains(_category) && categories.isNotEmpty) {
            _category = categories.first;
          }
          final presets = eq.presetsInCategory(_category);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Equalizer enabled'),
                subtitle: Text(
                  '${eq.hardwareBandCount} hardware bands • preset: ${eq.preset}',
                ),
                value: eq.isEnabled,
                onChanged: eq.setEnabled,
              ),
              const SizedBox(height: 8),
              Text('Preamp', style: Theme.of(context).textTheme.titleMedium),
              Slider(
                value: eq.preamp.clamp(-12.0, 6.0),
                min: -12,
                max: 6,
                divisions: 36,
                label: '${eq.preamp.toStringAsFixed(1)} dB',
                onChanged: eq.setPreamp,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('-12 dB'),
                  Text('0'),
                  Text('+6 dB'),
                ],
              ),
              const SizedBox(height: 16),
              Text('Presets', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in presets)
                    InputChip(
                      label: Text(p.name),
                      selected: eq.preset == p.name,
                      onPressed: () => eq.applyPreset(p.name),
                      onDeleted: p.isCustom ? () => eq.deleteCustomPreset(p.name) : null,
                      deleteIcon: p.isCustom ? const Icon(Icons.close, size: 16) : null,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Bands',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Sliders follow this device’s DSP (${eq.hardwareBandCount} bands). '
                'Presets are authored as a 10-band studio curve and mapped to hardware.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final band in eq.bandStates)
                      Expanded(
                        child: _BandSlider(
                          band: band,
                          onChanged: (v) => eq.setBandGain(band.index, v),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveCustom(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'My mix',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await context.read<EqualizerProvider>().saveCustomPreset(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved preset “${name.trim()}”')),
    );
  }

}

String _eqFormatFrequency(double hz) {
  if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k';
  return '${hz.round()}';
}

class _BandSlider extends StatelessWidget {
  final EqualizerBandState band;
  final ValueChanged<double> onChanged;

  const _BandSlider({required this.band, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(0)}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: band.gain.clamp(band.minGain, band.maxGain),
              min: band.minGain,
              max: band.maxGain,
              divisions: 48,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          _eqFormatFrequency(band.centerFrequency),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
