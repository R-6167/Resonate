import 'package:flutter/material.dart';
import '../ui/resonate_glass.dart';
import 'package:provider/provider.dart';
import '../providers/audio_visualization_provider.dart';
import '../widgets/ask_resonate/ask_resonate_controller.dart';

class AudioVisualizationSettingsScreen extends StatelessWidget {
  const AudioVisualizationSettingsScreen({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) {
    return ResonateGlassScaffold(title: const Text('Visualization & Orb'), body: Consumer<AudioVisualizationProvider>(builder: (context, p, _) {
      final shapeController = context.watch<AskResonateController>();
      final types = {'bars':'Spectrum Bars','waveform':'Waveform','circular':'Circular Spectrum','wave':'Animated Wave'};
      return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        _header(context),
        const Padding(padding: EdgeInsets.fromLTRB(16,20,16,8), child: Text('General', style: TextStyle(fontWeight: FontWeight.bold))),
        SwitchListTile(title: const Text('Enable Visualization'), subtitle: const Text('Show animated graphics while music is playing'), secondary: const Icon(Icons.graphic_eq), value: p.enabled, onChanged: p.setEnabled),
        ListTile(leading: const Icon(Icons.auto_graph), title: const Text('Visualization Type'), subtitle: Text(types[p.visualizationType] ?? p.visualizationType), trailing: const Icon(Icons.chevron_right), enabled: p.enabled, onTap: p.enabled ? () => _chooseType(context, p, types) : null),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16,20,16,8), child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold))),
        SwitchListTile(title: const Text('Mirror Visualization'), value: p.mirror, onChanged: p.enabled ? p.setMirror : null),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16,20,16,8), child: Text('Ask Resonate Orb', style: TextStyle(fontWeight: FontWeight.bold))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Overlay shape'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in <(AskResonateShape, String)>[
                    (AskResonateShape.blob, 'Blob'),
                    (AskResonateShape.capsule, 'Capsule'),
                    (AskResonateShape.semicircle, 'Edge'),
                    (AskResonateShape.orbital, 'Orbital'),
                  ])
                    ChoiceChip(
                      label: Text(option.$2),
                      selected: shapeController.shape == option.$1,
                      onSelected: (_) => shapeController.setShape(option.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
        SwitchListTile(title: const Text('Audio-reactive movement'), subtitle: const Text('Use the live low-frequency spectrum to pulse the orb and overlay shape'), value: p.orbAudioReactive, onChanged: p.enabled ? p.setOrbAudioReactive : null),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16,20,16,8), child: Text('Audio Response', style: TextStyle(fontWeight: FontWeight.bold))),
        SwitchListTile(title: const Text('Bass Response'), subtitle: const Text('Emphasize low-frequency movement'), value: p.reactToBass, onChanged: p.enabled ? p.setReactToBass : null),
        _slider(context, 'Sensitivity', p.sensitivity, 0.1, 1.0, p.setSensitivity, '${(p.sensitivity*100).round()}%'),
        _slider(context, 'Smoothing', p.smoothing, 0, 1, p.setSmoothing, '${(p.smoothing*100).round()}%'),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16,20,16,8), child: Text('Performance', style: TextStyle(fontWeight: FontWeight.bold))),
        SwitchListTile(title: const Text('Smooth Animation'), subtitle: const Text('Use continuous motion when enabled'), value: p.smoothAnimation, onChanged: p.enabled ? p.setSmoothAnimation : null),
        _slider(context, 'Frame Rate', p.frameRate, 12, 30, p.setFrameRate, '${p.frameRate.round()} FPS', divisions: 9),
        const Padding(padding: EdgeInsets.all(16), child: ResonateGlassCard(child: Padding(padding: EdgeInsets.all(16), child: Text('Both the main visualizer and Ask Resonate use the same native playback spectrum. Capture is optional, low-rate, and fails silently on unsupported devices; it does not modify the audio path.')))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: OutlinedButton.icon(onPressed: p.reset, icon: const Icon(Icons.restore), label: const Text('Reset Visualization Settings'))),
      ]);
    }));
  }
  Widget _header(BuildContext context) => Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: Theme.of(context).colorScheme.surfaceContainerHighest), child: Column(children: [Icon(Icons.graphic_eq_rounded, size: 52, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 10), Text('Audio Visualization & Orb', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 6), const Text('A lightweight, shared audio-reactive layer for Now Playing and Ask Resonate.', textAlign: TextAlign.center)]));
  Widget _slider(BuildContext context, String title, double value, double min, double max, ValueChanged<double> onChanged, String label, {int? divisions}) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title), Text(label, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold))]), Slider(value: value, min: min, max: max, divisions: divisions ?? 18, onChanged: onChanged)]));
  Future<void> _chooseType(BuildContext context, AudioVisualizationProvider p, Map<String,String> types) async { await showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Visualization Type'), content: Column(mainAxisSize: MainAxisSize.min, children: types.entries.map((entry) => RadioListTile<String>(title: Text(entry.value), value: entry.key, groupValue: p.visualizationType, onChanged: (value) { if (value != null) { p.setVisualizationType(value); Navigator.pop(context); } })).toList()))); }
}
