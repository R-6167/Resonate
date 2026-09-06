import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_mix.dart';
import '../providers/intelligence_mix_controller.dart';

/// A small Home/For You surface for the latest generated mix journey.
/// It deliberately exposes evidence rather than inventing personality traits.
class EvolvingMixCard extends StatelessWidget {
  const EvolvingMixCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<IntelligenceMixController>();
    final current = controller.currentMix;
    if (current != null && current.edition > 1) {
      return _JourneyCard(mix: current, continuity: controller.currentContinuity, canEvolve: true);
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: controller.recentGeneratedMixes(),
      builder: (context, snapshot) {
        final values = snapshot.data ?? const <Map<String, dynamic>>[];
        if (values.isEmpty) return const SizedBox.shrink();
        final latest = values.first;
        final edition = (latest['edition'] as num?)?.toInt() ?? 1;
        if (edition <= 1) return const SizedBox.shrink();
        final mix = _metadataMix(latest);
        if (mix == null) return const SizedBox.shrink();
        return _JourneyCard(mix: mix, continuity: {'score': latest['previousContinuityScore']});
      },
    );
  }

  IntelligenceMix? _metadataMix(Map<String, dynamic> value) {
    final id = value['id'] as String?;
    final title = value['title'] as String?;
    final description = value['description'] as String?;
    final reason = value['reason'] as String?;
    final createdAt = DateTime.tryParse(value['createdAt'] as String? ?? '');
    final targetMinutes = (value['targetMinutes'] as num?)?.toInt();
    final edition = (value['edition'] as num?)?.toInt() ?? 1;
    if (id == null || title == null || description == null || reason == null || createdAt == null || targetMinutes == null) return null;
    return IntelligenceMix(
      id: id,
      title: title,
      description: description,
      songs: const [],
      targetDuration: Duration(minutes: targetMinutes),
      createdAt: createdAt,
      reason: reason,
      parentMixId: value['parentMixId'] as String?,
      edition: edition,
      previousContinuityScore: (value['previousContinuityScore'] as num?)?.toDouble(),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final IntelligenceMix mix;
  final Map<String, dynamic>? continuity;
  final bool canEvolve;

  const _JourneyCard({required this.mix, this.continuity, this.canEvolve = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = (continuity?['score'] as num?)?.toDouble() ?? mix.previousContinuityScore;
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
        onTap: canEvolve ? context.read<IntelligenceMixController>().evolveCurrentMix : null,
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
              Text(canEvolve ? '${mix.songs.length} tracks' : 'Remembered journey'),
              const SizedBox(width: 14),
              Icon(Icons.schedule_outlined, size: 17, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('${mix.targetDuration.inMinutes} min target'),
              const Spacer(),
              if (canEvolve) Text('Evolve again', style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ),
    );
  }
}
