import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/intelligence_mix_controller.dart';

/// A small Home/For You surface for the latest generated mix journey.
/// It deliberately exposes evidence rather than inventing personality traits.
class EvolvingMixCard extends StatelessWidget {
  const EvolvingMixCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<IntelligenceMixController>();
    final mix = controller.currentMix;
    final continuity = controller.currentContinuity;
    if (mix == null || mix.edition <= 1) return const SizedBox.shrink();

    final score = (continuity?['score'] as num?)?.toDouble();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final evidence = score == null
        ? mix.reason
        : score >= .65
            ? 'You stayed with the previous edition, so its strongest path is being kept.'
            : score <= .35
                ? 'The previous edition did not land as well, so this version opens a different path.'
                : 'This edition keeps useful signals from the previous journey while making room for change.';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: controller.isLoading ? null : controller.evolveCurrentMix,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 16, 17, 15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(13)),
                child: Icon(Icons.auto_awesome_rounded, color: scheme.primary),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your mix has evolved', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('Edition ${mix.edition}', style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary)),
              ])),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ]),
            const SizedBox(height: 12),
            Text(mix.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(evidence, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 11),
            Row(children: [
              Icon(Icons.library_music_outlined, size: 17, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('${mix.songs.length} tracks'),
              const SizedBox(width: 14),
              Icon(Icons.schedule_outlined, size: 17, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('${mix.targetDuration.inMinutes} min target'),
              const Spacer(),
              Text('Evolve again', style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ),
    );
  }
}
