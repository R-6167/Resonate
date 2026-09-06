import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/autopilot_controller.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../services/intelligence_companion_profile.dart';

class AutopilotTakeoverCard extends StatefulWidget {
  const AutopilotTakeoverCard({super.key});
  @override State<AutopilotTakeoverCard> createState() => _AutopilotTakeoverCardState();
}

class _AutopilotTakeoverCardState extends State<AutopilotTakeoverCard> {
  late Future<IntelligenceCompanionProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<IntelligenceCompanionProfile> _loadProfile() => IntelligenceCompanionProfile.build(context.read<IntelligenceProvider>());

  void _refreshProfile() => setState(() => _profileFuture = _loadProfile());

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AutopilotController>();
    final intelligence = context.watch<IntelligenceProvider>();
    if (!intelligence.isEnabled) return const SizedBox.shrink();
    final music = context.read<MusicProvider>();
    Song? pendingSong;
    if (controller.hasPendingTakeover) {
      for (final item in music.queue) {
        if (item.id == controller.pendingSongId) { pendingSong = item; break; }
      }
    }
    final scheme = Theme.of(context).colorScheme;
    final next = intelligence.anticipatedNext;

    return FutureBuilder<IntelligenceCompanionProfile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        return Column(children: [
          if (pendingSong != null)
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                child: Row(children: [
                  Icon(Icons.smart_toy_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Autopilot is ready', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
                    const SizedBox(height: 2),
                    Text('Next: ${pendingSong!.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                    Text('I chose this from your listening pattern.', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ])),
                  TextButton(onPressed: controller.denyPendingTakeover, child: const Text('Keep current')),
                  FilledButton(onPressed: controller.allowPendingTakeover, child: const Text('Let it choose')),
                ]),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.psychology_rounded, color: scheme.primary),
                  const SizedBox(width: 9),
                  Expanded(child: Text('Companion memory', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  if (profile != null && profile.confidence > 0) Padding(padding: const EdgeInsets.only(right: 4), child: Text('${(profile.confidence * 100).round()}%', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary))),
                  IconButton(tooltip: 'Refresh memory', onPressed: _refreshProfile, icon: const Icon(Icons.refresh_rounded), visualDensity: VisualDensity.compact),
                ]),
                if (profile == null) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ] else ...[
                  const SizedBox(height: 5),
                  Text(profile.tendency, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(profile.explanation, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 9),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    Chip(label: Text('Window: ${profile.primarySignal}'), visualDensity: VisualDensity.compact),
                    if (profile.secondarySignal.isNotEmpty) Chip(label: Text('Long-term: ${profile.secondarySignal}'), visualDensity: VisualDensity.compact),
                    if (profile.windowEvents > 0) Chip(label: Text('${profile.windowEvents} signals'), visualDensity: VisualDensity.compact),
                    if (profile.completed > 0) Chip(label: Text('${profile.completed} finished'), visualDensity: VisualDensity.compact),
                    if (profile.skipped > 0) Chip(label: Text('${profile.skipped} skipped'), visualDensity: VisualDensity.compact),
                    if (profile.learnedEvents > 0) Chip(label: Text('${profile.learnedEvents} learned'), visualDensity: VisualDensity.compact),
                    if (profile.momentum >= .5) const Chip(label: Text('Pattern holding'), visualDensity: VisualDensity.compact),
                  ]),
                  const SizedBox(height: 10),
                  Text('How I see your listening', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
                  const SizedBox(height: 7),
                  _SignalBar(label: 'Familiarity', value: profile.familiarityAffinity),
                  _SignalBar(label: 'Exploration', value: profile.explorationAffinity),
                  _SignalBar(label: 'Artist variety', value: profile.artistDiversity),
                  _SignalBar(label: 'Feedback alignment', value: profile.feedbackAlignment),
                  const SizedBox(height: 8),
                  Text(profile.context, style: Theme.of(context).textTheme.labelMedium),
                ],
                if (next != null) ...[
                  const SizedBox(height: 10),
                  Divider(color: scheme.outlineVariant),
                  const SizedBox(height: 7),
                  Text('Why this next', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
                  const SizedBox(height: 4),
                  Text(next.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                  if (next.sessionReason.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(next.sessionReason, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

class _SignalBar extends StatelessWidget {
  final String label;
  final double value;

  const _SignalBar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 112, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value.clamp(0.0, 1.0).toDouble(), minHeight: 5, backgroundColor: scheme.surfaceContainerHighest),
        )),
        const SizedBox(width: 8),
        SizedBox(width: 34, child: Text('${(value * 100).round()}%', textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelSmall)),
      ]),
    );
  }
}
