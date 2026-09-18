import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_mix.dart';
import '../providers/intelligence_mix_controller.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';

/// Deep Companion mix surface — compact journey card on For you.
class EvolvingMixCard extends StatefulWidget {
  const EvolvingMixCard({super.key});
  @override
  State<EvolvingMixCard> createState() => _EvolvingMixCardState();
}

class _EvolvingMixCardState extends State<EvolvingMixCard> {
  Future<List<Map<String, dynamic>>>? _memoryFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _memoryFuture ??= context.read<IntelligenceMixController>().recentGeneratedMixes();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<IntelligenceMixController>();
    final intelligence = context.watch<IntelligenceProvider>();
    if (!intelligence.isEnabled) return const SizedBox.shrink();
    final current = controller.currentMix;
    if (current != null) {
      return _JourneyCard(
        mix: current,
        continuity: controller.currentContinuity,
        canEvolve: current.songs.isNotEmpty,
        loading: controller.isLoading,
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _memoryFuture,
      builder: (context, snapshot) {
        final values = snapshot.data ?? const <Map<String, dynamic>>[];
        if (values.isEmpty) return _GenerateCard(loading: controller.isLoading);
        final latest = _metadataMix(values.first);
        if (latest == null) return _GenerateCard(loading: controller.isLoading);
        return _JourneyCard(
          mix: latest,
          continuity: {'score': latest.previousContinuityScore},
          canEvolve: false,
          loading: controller.isLoading,
        );
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
    if (id == null || title == null || description == null || reason == null || createdAt == null || targetMinutes == null) {
      return null;
    }
    return IntelligenceMix(
      id: id,
      title: title,
      description: description,
      songs: const [],
      targetDuration: Duration(minutes: targetMinutes),
      reason: reason,
      createdAt: createdAt,
      previousContinuityScore: (value['continuityScore'] as num?)?.toDouble() ?? 0,
    );
  }
}

class _GenerateCard extends StatelessWidget {
  final bool loading;
  const _GenerateCard({required this.loading});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = context.read<IntelligenceMixController>();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        gradient: LinearGradient(
          colors: [
            scheme.tertiaryContainer.withValues(alpha: 0.35),
            scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: scheme.tertiary.withValues(alpha: 0.18),
            child: Icon(Icons.route_rounded, color: scheme.tertiary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automatic mix',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'A short local journey from your library — evolves as you listen.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: loading ? null : () => controller.generateMix(),
            child: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final IntelligenceMix mix;
  final Map<String, dynamic>? continuity;
  final bool canEvolve;
  final bool loading;

  const _JourneyCard({
    required this.mix,
    this.continuity,
    required this.canEvolve,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = context.read<IntelligenceMixController>();
    final music = context.read<MusicProvider>();
    final score = (continuity?['score'] as num?)?.toDouble() ?? mix.previousContinuityScore;
    final minutes = mix.targetDuration.inMinutes;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_fix_rounded, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mix.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (score != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(score * 100).round()}% flow',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              mix.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('~$minutes min', style: Theme.of(context).textTheme.labelSmall),
                if (mix.songs.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.queue_music_rounded, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${mix.songs.length} tracks', style: Theme.of(context).textTheme.labelSmall),
                ],
              ],
            ),
            if (mix.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                mix.reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (mix.songs.isNotEmpty)
                  FilledButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            await music.playSong(
                              mix.songs.first,
                              queue: mix.songs,
                              startIndex: 0,
                            );
                          },
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Play mix'),
                  ),
                if (canEvolve) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: loading ? null : () => controller.evolveCurrentMix(),
                    child: const Text('Evolve'),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'New mix',
                  onPressed: loading ? null : () => controller.generateMix(),
                  icon: loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
