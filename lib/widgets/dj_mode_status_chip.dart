import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/dj_mode_provider.dart';
import '../screens/dj_mode_settings_screen.dart';

/// Compact status chip — matches Engine A/B chip language on Now Playing.
/// Only visible when DJ Mode master is on.
class DjModeStatusChip extends StatelessWidget {
  const DjModeStatusChip({
    super.key,
    this.dense = false,
    this.showWhenOff = false,
  });

  final bool dense;
  final bool showWhenOff;

  @override
  Widget build(BuildContext context) {
    return Consumer<DjModeProvider>(
      builder: (context, dj, _) {
        if (!dj.isLoaded) return const SizedBox.shrink();
        if (!dj.isEnabled && !showWhenOff) return const SizedBox.shrink();

        final parts = <String>[];
        if (dj.isEnabled) {
          if (dj.beatAlignActive) parts.add('beat');
          if (dj.tempoMatchActive) parts.add('tempo');
          if (dj.harmonicMixActive) parts.add('key');
        }
        final label = !dj.isEnabled
            ? 'DJ off'
            : (parts.isEmpty ? 'DJ' : 'DJ · ${parts.take(2).join(' · ')}');

        final scheme = Theme.of(context).colorScheme;
        final chip = Chip(
          visualDensity:
              dense ? VisualDensity.compact : VisualDensity.standard,
          avatar: Icon(
            Icons.headphones_rounded,
            size: dense ? 15 : 17,
            color: dj.isEnabled ? scheme.primary : scheme.onSurfaceVariant,
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: dense ? 11.5 : 13,
              fontWeight: FontWeight.w600,
              color: dj.isEnabled ? null : scheme.onSurfaceVariant,
            ),
          ),
          side: dj.isEnabled
              ? BorderSide(color: scheme.primary.withValues(alpha: 0.35))
              : null,
        );

        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DjModeSettingsScreen(),
                ),
              );
            },
            child: chip,
          ),
        );
      },
    );
  }
}

/// One-line status banner for Crossfade / Queue when DJ is on.
class DjModeStatusBanner extends StatelessWidget {
  const DjModeStatusBanner({super.key, this.contextLabel});

  /// Optional extra context, e.g. "may adjust seek and length".
  final String? contextLabel;

  @override
  Widget build(BuildContext context) {
    return Consumer<DjModeProvider>(
      builder: (context, dj, _) {
        if (!dj.isLoaded || !dj.isEnabled) return const SizedBox.shrink();
        final bits = <String>[];
        if (dj.beatAlignActive) bits.add('beat align');
        if (dj.tempoMatchActive) bits.add('tempo match');
        if (dj.harmonicMixActive) bits.add('harmonic bias');
        if (dj.transitionSfx) bits.add('transition FX');
        final detail = bits.isEmpty
            ? 'DJ Mode is on'
            : 'DJ Mode: ${bits.join(' · ')}';
        final extra = contextLabel;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.35),
          child: ListTile(
            dense: true,
            leading: Icon(
              Icons.headphones_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              detail,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: extra != null ? Text(extra) : null,
            trailing: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DjModeSettingsScreen(),
                  ),
                );
              },
              child: const Text('Settings'),
            ),
          ),
        );
      },
    );
  }
}
