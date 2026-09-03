import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/equalizer_provider.dart';

class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          Consumer<EqualizerProvider>(
            builder: (context, eq, _) => Switch(
              value: eq.isEnabled,
              onChanged: eq.setEnabled,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
            onPressed: () => context.read<EqualizerProvider>().reset(),
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
                  'The Android audio equalizer is not available yet.\n\nStart playing a song, then return here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              '10-band style EQ',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(eq.preset),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Live Android processing. The available hardware bands are used automatically on your device.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 300,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: eq.bandStates.map((band) {
                            return Expanded(
                              child: _BandSlider(
                                band: band,
                                onChanged: (value) => eq.setBandGain(band.index, value),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Presets', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  'Flat',
                  'Bass Boost',
                  'Treble Boost',
                  'Vocal',
                  'Rock',
                  'Pop',
                  'Jazz',
                  'Classical',
                  'Electronic',
                ].map((name) => _PresetChip(name)).toList(),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preamp', style: Theme.of(context).textTheme.titleMedium),
                      Slider(
                        value: eq.preamp,
                        min: -12,
                        max: 6,
                        divisions: 36,
                        label: '${eq.preamp.toStringAsFixed(1)} dB',
                        onChanged: eq.setPreamp,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [Text('-12 dB'), Text('0 dB'), Text('+6 dB')],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Live bands', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...eq.bandStates.map((band) => ListTile(
                    leading: const Icon(Icons.graphic_eq),
                    title: Text(_formatFrequency(band.centerFrequency)),
                    subtitle: LinearProgressIndicator(
                      value: ((band.gain - band.minGain) / (band.maxGain - band.minGain)).clamp(0.0, 1.0),
                    ),
                    trailing: Text('${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB'),
                  )),
            ],
          );
        },
      ),
    );
  }

  static String _formatFrequency(double hz) {
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)} kHz';
    return '${hz.round()} Hz';
  }
}

class _BandSlider extends StatelessWidget {
  final EqualizerBandState band;
  final ValueChanged<double> onChanged;

  const _BandSlider({required this.band, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(0)}'),
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
        Text(EqualizerScreen._formatFrequency(band.centerFrequency), textAlign: TextAlign.center),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String name;
  const _PresetChip(this.name);

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerProvider>();
    final selected = eq.preset == name;
    return FilterChip(
      selected: selected,
      label: Text(name),
      onSelected: (_) => eq.applyPreset(name),
    );
  }
}
