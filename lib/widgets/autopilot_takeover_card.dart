import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/autopilot_controller.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../services/intelligence_pattern_store.dart';

class AutopilotTakeoverCard extends StatelessWidget {
  const AutopilotTakeoverCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AutopilotController>();
    final intelligence = context.watch<IntelligenceProvider>();
    if (!intelligence.isEnabled) return const SizedBox.shrink();

    final music = context.read<MusicProvider>();
    Song? pendingSong;
    if (controller.hasPendingTakeover) {
      for (final item in music.queue) {
        if (item.id == controller.pendingSongId) {
          pendingSong = item;
          break;
        }
      }
    }

    final scheme = Theme.of(context).colorScheme;
    final next = intelligence.anticipatedNext;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Future.wait([
        IntelligencePatternStore.readBucket(DateTime.now()),
        IntelligencePatternStore.readStateProfile(),
      ]),
      builder: (context, snapshot) {
        final bucket = snapshot.data != null && snapshot.data!.isNotEmpty ? snapshot.data![0] : const <String, dynamic>{};
        final profile = snapshot.data != null && snapshot.data!.length > 1 ? snapshot.data![1] : const <String, dynamic>{};
        final bucketState = IntelligencePatternStore.stateFor(bucket);
        final globalState = IntelligencePatternStore.globalState(profile);
        final globalConfidence = IntelligencePatternStore.stateConfidence(profile);
        final momentum = IntelligencePatternStore.stateMomentum(profile);
        final bucketEvents = (bucket['events'] as num?)?.toInt() ?? 0;
        final bucketCompleted = (bucket['completed'] as num?)?.toInt() ?? 0;
        final bucketSkipped = (bucket['skipped'] as num?)?.toInt() ?? 0;

        return Column(
          children: [
            if (pendingSong != null)
              Card(
                color: scheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                  child: Row(
                    children: [
                      Icon(Icons.smart_toy_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Autopilot is ready', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
                            const SizedBox(height: 2),
                            Text('Next: ${pendingSong!.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                            Text('I chose this from your listening pattern.', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      TextButton(onPressed: controller.denyPendingTakeover, child: const Text('Keep current')),
                      FilledButton(onPressed: controller.allowPendingTakeover, child: const Text('Let it choose')),
                    ],
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.psychology_rounded, color: scheme.primary),
                        const SizedBox(width: 9),
                        Expanded(child: Text('Companion memory', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                        Chip(label: Text(globalState), visualDensity: VisualDensity.compact),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      IntelligencePatternStore.explanationFor(bucketState, bucket),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Chip(label: Text('This window: $bucketState'), visualDensity: VisualDensity.compact),
                        if (bucketEvents > 0) Chip(label: Text('$bucketEvents signals'), visualDensity: VisualDensity.compact),
                        if (bucketCompleted > 0) Chip(label: Text('$bucketCompleted finished'), visualDensity: VisualDensity.compact),
                        if (bucketSkipped > 0) Chip(label: Text('$bucketSkipped skipped'), visualDensity: VisualDensity.compact),
                        if (globalConfidence >= .55) Chip(label: Text('${(globalConfidence * 100).round()}% consistent'), visualDensity: VisualDensity.compact),
                        if (momentum >= .5) const Chip(label: Text('Pattern holding'), visualDensity: VisualDensity.compact),
                      ],
                    ),
                    if (next != null) ...[
                      const SizedBox(height: 10),
                      Divider(color: scheme.outlineVariant),
                      const SizedBox(height: 8),
                      Text('Why this next', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
                      const SizedBox(height: 4),
                      Text(next.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                      if (next.sessionReason.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(next.sessionReason, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
