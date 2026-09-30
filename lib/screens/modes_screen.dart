import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playback_policy.dart';
import '../models/resonate_mode.dart';
import '../providers/mode_provider.dart';
import '../ui/resonate_glass.dart';

/// Mode picker — policy profiles only; does not fork the playback engine.
class ModesScreen extends StatelessWidget {
  const ModesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResonateGlassScaffold(
      title: const Text('Modes'),
      body: Consumer<ModeProvider>(
        builder: (context, modes, _) {
          final active = modes.mode;
          final policy = modes.policy;
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 36),
            children: [
              ResonateGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modes change how Resonate behaves — not just what plays.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Active: ${active.emoji} ${active.label}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _policySummary(policy),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final mode in ResonateMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ResonateGlassCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: Text(mode.emoji, style: const TextStyle(fontSize: 22)),
                      title: Text(mode.label),
                      subtitle: Text(mode.shortDescription),
                      trailing: active == mode
                          ? Icon(Icons.check_circle_rounded,
                              color: Theme.of(context).colorScheme.primary)
                          : const Icon(Icons.circle_outlined),
                      onTap: () => modes.setMode(mode),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _policySummary(PlaybackPolicy p) {
    final bits = <String>[
      p.crossfadeAllowed ? 'Crossfade allowed' : 'Crossfade off',
      p.preciseResume ? 'Precise resume' : 'Standard resume',
      switch (p.uiDensity) {
        UiDensity.full => 'Full UI',
        UiDensity.reduced => 'Reduced UI',
        UiDensity.minimal => 'Minimal UI',
      },
      if (p.automationElevated) 'Elevated automation',
      if (p.preferLongSessions) 'Long sessions',
    ];
    return bits.join(' · ');
  }
}
