import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import '../providers/autopilot_controller.dart';
import '../providers/intelligence_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../screens/intelligence_settings_screen.dart';
import 'animated_companion_mark.dart';

/// Combined Intelligence + Autopilot surface for the For you dashboard.
/// Replaces the old separate hero tile, Autopilot card, and “A little nudge” card.
class AutopilotHomeCard extends StatelessWidget {
  final int songCount;

  const AutopilotHomeCard({super.key, this.songCount = 0});

  @override
  Widget build(BuildContext context) {
    final intelligence = context.watch<IntelligenceProvider>();
    final autopilot = context.watch<AutopilotController>();
    final music = context.watch<MusicProvider>();
    final scheme = Theme.of(context).colorScheme;
    final next = intelligence.anticipatedNext;

    Song? pendingSong;
    if (autopilot.hasPendingTakeover && autopilot.pendingSongId != null) {
      for (final s in music.queue) {
        if (s.id == autopilot.pendingSongId) {
          pendingSong = s;
          break;
        }
      }
      if (pendingSong == null) {
        for (final r in intelligence.recommendations) {
          if (r.song.id == autopilot.pendingSongId) {
            pendingSong = r.song;
            break;
          }
        }
      }
    }

    final headline = !intelligence.isEnabled
        ? 'Your player is fully manual'
        : intelligence.isAutopilot
            ? (autopilot.consentGranted
                ? 'Autopilot can guide what plays next'
                : 'Autopilot is ready — waiting for your say')
            : intelligence.autonomy == 1
                ? 'Assisting with local suggestions'
                : 'Quiet suggestions from your library';

    final status = _statusLabel(intelligence, autopilot);
    final statusColor = _statusColor(scheme, intelligence, autopilot);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.95),
            scheme.surfaceContainerHighest.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // —— Hero header ——
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 0),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  child: AnimatedCompanionMark(
                    mode: intelligence.isEnabled ? intelligence.autonomyLabel : 'OFF',
                    size: 28,
                    key: ValueKey(intelligence.isEnabled ? intelligence.autonomyLabel : 'off'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resonate Intelligence',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        intelligence.isEnabled
                            ? 'Local-first · stays on this device'
                            : 'Predictions and Autopilot are off',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Text(
              headline,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                const Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('Local-first'),
                ),
                const Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('Explainable'),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('$songCount songs'),
                ),
              ],
            ),
          ),

          // —— Mode + consent ——
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!intelligence.isEnabled)
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text('Enable Intelligence'),
                    subtitle: const Text('Turn on local suggestions and Autopilot options'),
                    value: false,
                    onChanged: (v) {
                      if (v) intelligence.setEnabled(true);
                    },
                  )
                else ...[
                  Text('Mode', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Suggest')),
                      ButtonSegment(value: 1, label: Text('Assist')),
                      ButtonSegment(value: 2, label: Text('Auto')),
                    ],
                    selected: {intelligence.autonomy},
                    onSelectionChanged: (v) => intelligence.setAutonomy(v.first),
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text('May change tracks'),
                    subtitle: Text(
                      autopilot.consentGranted
                          ? 'Can enqueue, skip, and crossfade'
                          : 'Advisory only — won’t change the current track',
                    ),
                    value: autopilot.consentGranted,
                    onChanged: intelligence.isAutopilot ? (v) => autopilot.setConsent(v) : null,
                  ),
                ],
              ],
            ),
          ),

          // —— Nudge / next pick (single place, not duplicated elsewhere) ——
          if (intelligence.isEnabled && (pendingSong != null || next != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: pendingSong != null
                  ? _PendingTakeoverBlock(
                      song: pendingSong,
                      onAllow: () => autopilot.allowPendingTakeover(),
                      onDeny: () => autopilot.denyPendingTakeover(),
                    )
                  : _NudgeBlock(
                      item: next!,
                      canPlayNext: intelligence.isAutopilot && autopilot.consentGranted,
                      onPlayNext: () async {
                        await music.playNext(next.song);
                        await music.nextSong(source: 'autopilot_home_card');
                      },
                      onPlayNow: () async {
                        final list = intelligence.recommendations.map((r) => r.song).toList();
                        final index = list.indexWhere((s) => s.id == next.song.id);
                        final queue = index >= 0 ? list.sublist(index) : <Song>[next.song];
                        await music.playSong(next.song, queue: queue, startIndex: 0);
                      },
                    ),
            ),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen()),
              ),
              child: const Text('Intelligence settings'),
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(IntelligenceProvider intel, AutopilotController ap) {
    if (!intel.isEnabled) return 'Off';
    if (ap.hasPendingTakeover) return 'Waiting';
    if (intel.isAutopilot && ap.consentGranted) return 'Controlling';
    if (intel.isAutopilot) return 'Ready';
    if (intel.isAutopilotGraduated) return 'Graduated';
    return intel.autonomyLabel;
  }

  static Color _statusColor(ColorScheme scheme, IntelligenceProvider intel, AutopilotController ap) {
    if (ap.hasPendingTakeover) return scheme.tertiary;
    if (intel.isAutopilot && ap.consentGranted) return scheme.primary;
    if (intel.isAutopilot) return scheme.secondary;
    return scheme.onSurfaceVariant;
  }
}

class _PendingTakeoverBlock extends StatelessWidget {
  final Song song;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  const _PendingTakeoverBlock({
    required this.song,
    required this.onAllow,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wants to play next', style: Theme.of(context).textTheme.labelLarge),
            Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(onPressed: onAllow, child: const Text('Allow')),
                const SizedBox(width: 8),
                TextButton(onPressed: onDeny, child: const Text('Not now')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NudgeBlock extends StatelessWidget {
  final IntelligenceRecommendation item;
  final bool canPlayNext;
  final VoidCallback onPlayNext;
  final VoidCallback onPlayNow;

  const _NudgeBlock({
    required this.item,
    required this.canPlayNext,
    required this.onPlayNext,
    required this.onPlayNow,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confidence = (item.confidence.clamp(0.0, 1.0) * 100).round();

    return Material(
      color: scheme.surface.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
              child: Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A little nudge',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    item.song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${item.song.artist} · $confidence% · ${item.reason}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Play now',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: onPlayNow,
            ),
            if (canPlayNext)
              IconButton(
                tooltip: 'Queue as next',
                icon: const Icon(Icons.playlist_play_rounded),
                onPressed: onPlayNext,
              ),
          ],
        ),
      ),
    );
  }
}
