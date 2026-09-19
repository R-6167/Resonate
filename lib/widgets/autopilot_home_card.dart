import 'package:flutter/material.dart';
import '../providers/listening_history_provider.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import '../providers/autopilot_controller.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../screens/intelligence_settings_screen.dart';
import 'animated_companion_mark.dart';

/// Combined Intelligence surface for For you — hierarchy without mode picker
/// (mode lives in Settings). Session flow + nudge live inside this card.
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
    final textTheme = Theme.of(context).textTheme;

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
                : 'Autopilot is ready - waiting for your say')
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
          // —— Level 1: identity ——
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  child: AnimatedCompanionMark(
                    mode: intelligence.isEnabled ? intelligence.autonomyLabel : 'OFF',
                    size: 34,
                    key: ValueKey(intelligence.isEnabled ? intelligence.autonomyLabel : 'off'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resonate Intelligence',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        intelligence.isEnabled
                            ? 'Local-first · stays on this device'
                            : 'Predictions and Autopilot are off',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // —— Level 2: status line (smaller) ——
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Text(
              headline,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                height: 1.25,
                color: scheme.onSurface.withValues(alpha: 0.88),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _SmallChip(label: 'Local-first'),
                _SmallChip(label: 'Explainable'),
                _SmallChip(label: '$songCount songs'),
                if (intelligence.isEnabled)
                  _SmallChip(label: intelligence.autonomyLabel),
              ],
            ),
          ),

          // —— Level 3: listening flow (was separate card) ——
          if (intelligence.isEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Material(
                color: scheme.surface.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 42, height: 22, child: _InlineWaveDots()),
                          const SizedBox(width: 8),
                          Text(
                            'Your listening flow',
                            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        intelligence.sessionSummary,
                        style: textTheme.bodySmall?.copyWith(height: 1.35),
                      ),
                      if (intelligence.sessionArtists.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Flow: ${intelligence.sessionArtists.take(3).join(' · ')}',
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],

          // —— Consent only when Autopilot (no mode segmented control) ——
          if (intelligence.isEnabled && intelligence.isAutopilot)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                title: const Text('May change tracks', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  autopilot.consentGranted
                      ? 'Can enqueue, skip, and crossfade'
                      : 'Advisory only - will not change the current track',
                  style: const TextStyle(fontSize: 12),
                ),
                value: autopilot.consentGranted,
                onChanged: (v) => autopilot.setConsent(v),
              ),
            )
          else if (!intelligence.isEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                title: const Text('Enable Intelligence'),
                subtitle: const Text('Local suggestions and Autopilot options'),
                value: false,
                onChanged: (v) {
                  if (v) intelligence.setEnabled(true);
                },
              ),
            ),

          // —— Nudge / pending ——
          if (intelligence.isEnabled && (pendingSong != null || next != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
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

          // Compact listening snapshot footer
          Consumer<ListeningHistoryProvider>(
            builder: (context, history, _) {
              final stats = history.stats;
              final played = (stats['playedMs'] as num?)?.toInt() ?? 0;
              final completed = (stats['completed'] as num?)?.toInt() ?? 0;
              final skipped = (stats['skipped'] as num?)?.toInt() ?? 0;
              if (played <= 0 && completed <= 0) return const SizedBox.shrink();
              String hours() {
                final h = played / 3600000.0;
                if (h < 0.1) return '${(played / 60000).round()}m';
                return '${h.toStringAsFixed(1)}h';
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Icon(Icons.insights_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Listening · ${hours()} · $completed finished · $skipped skipped',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
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

class _SmallChip extends StatelessWidget {
  final String label;
  const _SmallChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _InlineWaveDots extends StatefulWidget {
  const _InlineWaveDots();
  @override
  State<_InlineWaveDots> createState() => _InlineWaveDotsState();
}

class _InlineWaveDotsState extends State<_InlineWaveDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (i) {
          final phase = (_c.value + i * 0.18) % 1.0;
          final wave = (0.5 + 0.5 * _sin(phase * 6.283185307)).clamp(0.0, 1.0);
          return Transform.translate(
            offset: Offset(0, -5 * wave),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          );
        }),
      ),
    );
  }

  double _sin(double x) {
    while (x > 3.1415926535) {
      x -= 6.283185307;
    }
    while (x < -3.1415926535) {
      x += 6.283185307;
    }
    final x2 = x * x;
    return x * (1 - x2 / 6 + (x2 * x2) / 120);
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
