import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/dj_mode_provider.dart';
import '../providers/music_provider.dart';
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

/// Shows why the last DJ handoff chose its strategy (kind + confidence).
/// Visible for a short window after a transition while DJ Mode is on.
class DjTransitionReasonChip extends StatelessWidget {
  const DjTransitionReasonChip({super.key});

  static String labelForStrategy(String? raw) {
    switch (raw) {
      case 'safeCrossfade':
        return 'Safe crossfade';
      case 'phraseBlend':
        return 'Phrase blend';
      case 'beatBlend':
        return 'Beat blend';
      case 'outroIntro':
        return 'Outro → intro';
      case 'breakdownDrop':
        return 'Breakdown → drop';
      case 'energyBridge':
        return 'Energy bridge';
      case 'beat_align':
        return 'Beat align';
      case 'safe_fallback':
        return 'Safe fallback';
      default:
        if (raw == null || raw.isEmpty) return 'DJ transition';
        // snake_case or camelCase fallback
        final spaced = raw
            .replaceAllMapped(
              RegExp(r'([a-z])([A-Z])'),
              (m) => '${m[1]} ${m[2]}',
            )
            .replaceAll('_', ' ');
        return spaced.isEmpty
            ? 'DJ transition'
            : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<DjModeProvider, MusicProvider>(
      builder: (context, dj, music, _) {
        if (!dj.isLoaded || !dj.isEnabled) return const SizedBox.shrink();
        if (!music.hasRecentDjTransition) return const SizedBox.shrink();

        final kind = labelForStrategy(music.lastDjStrategy);
        final conf = music.lastDjTransitionConfidence;
        final score = music.lastDjTransitionScore;
        final risks = music.lastDjTransitionRisks;

        final confPct =
            conf == null ? null : (conf.clamp(0.0, 1.0) * 100).round();
        final scorePct =
            score == null ? null : (score.clamp(0.0, 1.0) * 100).round();

        final parts = <String>[kind];
        if (confPct != null) parts.add('$confPct% conf');
        if (scorePct != null && scorePct != confPct) {
          parts.add('$scorePct% score');
        }

        final scheme = Theme.of(context).colorScheme;
        final riskHint = risks.isEmpty
            ? null
            : risks.take(2).map(_riskLabel).join(' · ');

        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Align(
            alignment: Alignment.center,
            child: Material(
              color: scheme.primaryContainer.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DjModeSettingsScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              parts.join(' · '),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (riskHint != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          riskHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _riskLabel(String raw) {
    switch (raw) {
      case 'bassCollision':
        return 'bass risk';
      case 'energyShock':
        return 'energy jump';
      case 'harmonicConflict':
        return 'key tension';
      case 'structureCollision':
        return 'structure clash';
      case 'tempoInstability':
        return 'tempo drift';
      case 'lowConfidence':
        return 'low analysis';
      default:
        return raw.replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m[1]} ${m[2]?.toLowerCase()}',
        );
    }
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
