import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playback_policy.dart';
import '../models/resonate_mode.dart';
import '../providers/mode_provider.dart';

/// Reference UI for the standalone Modes module.
class ModesScreen extends StatelessWidget {
  const ModesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resonate Modes')),
      body: Consumer<ModeProvider>(
        builder: (context, modes, _) {
          final active = modes.mode;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Modes change how Resonate behaves — not just what plays.',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Active: ${active.emoji} ${active.label}'),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                title: const Text('Auto-enter Driving in the car'),
                subtitle: const Text('Switch automatically when car context is detected.'),
                value: modes.autoEnterDrivingOnCar,
                onChanged: modes.setAutoEnterDrivingOnCar,
              ),
              const Divider(),
              for (final mode in ResonateMode.values)
                ListTile(
                  leading: Text(mode.emoji, style: const TextStyle(fontSize: 24)),
                  title: Text(mode.label),
                  subtitle: Text(mode.shortDescription),
                  trailing: active == mode
                      ? const Icon(Icons.check_circle)
                      : const Icon(Icons.circle_outlined),
                  onTap: () => modes.setMode(mode),
                ),
              const Divider(),
              Text(_policySummary(modes.policy)),
            ],
          );
        },
      ),
    );
  }

  String _policySummary(PlaybackPolicy p) {
    final density = switch (p.uiDensity) {
      UiDensity.full => 'Full UI',
      UiDensity.reduced => 'Reduced UI',
      UiDensity.minimal => 'Minimal UI',
    };
    return [
      p.crossfadeAllowed ? 'Crossfade allowed' : 'Crossfade off',
      p.preciseResume ? 'Precise resume' : 'Standard resume',
      density,
      if (p.automationElevated) 'Elevated automation',
      if (p.preferLongSessions) 'Long sessions',
    ].join(' · ');
  }
}
