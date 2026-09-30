import 'package:flutter/material.dart';
import '../ui/resonate_glass.dart';
import 'package:provider/provider.dart';

import '../providers/dj_mode_provider.dart';

/// Settings surface for optional DJ Mode (Intelligence-style master switch).
class DjModeSettingsScreen extends StatelessWidget {
  const DjModeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ResonateGlassScaffold(
      title: const Text('DJ Mode'),
      body: Consumer<DjModeProvider>(
        builder: (context, dj, _) {
          final on = dj.isEnabled;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'DJ transitions',
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Optional beat-aware handoffs, harmonic leans, and transition colour '
                'on top of crossfade. When off, Resonate is a normal offline player — nothing blocked.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 20),
              ResonateGlassCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
                  secondary: Icon(
                    Icons.headphones_rounded,
                    color: on ? scheme.primary : null,
                  ),
                  title: const Text(
                    'DJ Mode',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    on
                        ? 'Active — sub-features below may apply during transitions'
                        : 'Completely inactive; normal playback continues',
                  ),
                  value: on,
                  onChanged: dj.setEnabled,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Features',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _prefTile(
                context,
                enabled: on,
                title: 'Beat-aware handoff',
                subtitle: 'Start the next track on a beat of the current one when BPMs are close.',
                value: dj.beatAlign,
                onChanged: on ? dj.setBeatAlign : null,
              ),
              _prefTile(
                context,
                enabled: on,
                title: 'Tempo match',
                subtitle: 'Time-stretch during crossfade so tempos lock when BPMs differ (within max stretch).',
                value: dj.tempoMatch,
                onChanged: on ? dj.setTempoMatch : null,
              ),
              _prefTile(
                context,
                enabled: on,
                title: 'Harmonic mix',
                subtitle: 'Soft Camelot-key bias when Intelligence picks the next track (never a hard filter).',
                value: dj.harmonicMix,
                onChanged: on ? dj.setHarmonicMix : null,
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: on ? 1 : 0.45,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Max tempo stretch'),
                  subtitle: Text(
                    on
                        ? '±${dj.maxStretchPercent}% (used when tempo match is on)'
                        : 'Enable DJ Mode to adjust',
                  ),
                  trailing: Text('${dj.maxStretchPercent}%'),
                ),
              ),
              if (on)
                Slider(
                  value: dj.maxStretchPercent.toDouble(),
                  min: 3,
                  max: 20,
                  divisions: 17,
                  label: '±${dj.maxStretchPercent}%',
                  onChanged: (v) => dj.setMaxStretchPercent(v.round()),
                ),
              const SizedBox(height: 12),
              _prefTile(
                context,
                enabled: on,
                title: 'Transition SFX',
                subtitle:
                    'Light transition colour (reverb and related presets, picked at random). Restored after; never touches normal play.',
                value: dj.transitionSfx,
                onChanged: on ? dj.setTransitionSfx : null,
              ),
              _prefTile(
                context,
                enabled: on,
                title: 'Analyze library when idle',
                subtitle:
                    'Quiet background BPM / energy / structure scan while idle. Never blocks play.',
                value: dj.analyzeIdle,
                onChanged: on ? dj.setAnalyzeIdle : null,
              ),
              const SizedBox(height: 24),
              ResonateGlassCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'With Harmonic mix on, Intelligence may gently prefer Camelot-compatible '
                    'keys. Soft bias only — your taste still wins, missing keys stay neutral. '
                    'DJ Mode is optional and independent of Intelligence. Early skips teach the '
                    'planner which transitions to avoid next time.',
                    style: text.bodySmall,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _prefTile(
    BuildContext context, {
    required bool enabled,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
