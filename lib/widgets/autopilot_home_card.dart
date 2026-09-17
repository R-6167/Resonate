import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/autopilot_controller.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../screens/intelligence_settings_screen.dart';

/// Always-visible Autopilot status + controls on the For you (Home) dashboard.
class AutopilotHomeCard extends StatelessWidget {
  const AutopilotHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final intelligence = context.watch<IntelligenceProvider>();
    final autopilot = context.watch<AutopilotController>();
    final music = context.watch<MusicProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (!intelligence.isEnabled) {
      return Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Autopilot'),
          subtitle: const Text('Intelligence is off — enable it to use Autopilot'),
          trailing: TextButton(
            onPressed: () => intelligence.setEnabled(true),
            child: const Text('Enable'),
          ),
        ),
      );
    }

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

    final next = intelligence.anticipatedNext;
    final status = _statusLabel(intelligence, autopilot);
    final statusColor = _statusColor(scheme, intelligence, autopilot);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Autopilot',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Mode', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Suggest'), icon: Icon(Icons.lightbulb_outline, size: 16)),
                ButtonSegment(value: 1, label: Text('Assist'), icon: Icon(Icons.assistant_outlined, size: 16)),
                ButtonSegment(value: 2, label: Text('Auto'), icon: Icon(Icons.auto_awesome, size: 16)),
              ],
              selected: {intelligence.autonomy},
              onSelectionChanged: (v) => intelligence.setAutonomy(v.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('May change tracks'),
              subtitle: Text(
                autopilot.consentGranted
                    ? 'Autopilot can enqueue, skip, and crossfade'
                    : 'Advisory only — will not change the current track',
              ),
              value: autopilot.consentGranted,
              onChanged: intelligence.isAutopilot
                  ? (v) => autopilot.setConsent(v)
                  : null,
            ),
            if (pendingSong != null) ...[
              const SizedBox(height: 8),
              Material(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Wants to play next',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        pendingSong.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        pendingSong.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: () => autopilot.allowPendingTakeover(),
                            child: const Text('Allow'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => autopilot.denyPendingTakeover(),
                            child: const Text('Not now'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (next != null) ...[
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.skip_next_rounded),
                title: Text(
                  next.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${(next.confidence * 100).round()}% · ${next.reason}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: intelligence.isAutopilot && autopilot.consentGranted
                    ? IconButton(
                        tooltip: 'Play next now',
                        icon: const Icon(Icons.playlist_play_rounded),
                        onPressed: () async {
                          await music.playNext(next.song);
                          await music.nextSong(source: 'autopilot_home_card');
                        },
                      )
                    : null,
              ),
            ],
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
      ),
    );
  }

  static String _statusLabel(IntelligenceProvider intel, AutopilotController ap) {
    if (!intel.isEnabled) return 'Off';
    if (ap.hasPendingTakeover) return 'Waiting for you';
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
