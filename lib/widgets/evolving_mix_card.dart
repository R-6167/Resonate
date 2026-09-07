import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_mix.dart';
import '../providers/intelligence_mix_controller.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';

/// Deep Companion mix surface: generate, play, evaluate and evolve journeys.
class EvolvingMixCard extends StatefulWidget {
  const EvolvingMixCard({super.key});
  @override State<EvolvingMixCard> createState() => _EvolvingMixCardState();
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
    if (current != null) return _JourneyCard(mix: current, continuity: controller.currentContinuity, canEvolve: current.songs.isNotEmpty, loading: controller.isLoading);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _memoryFuture,
      builder: (context, snapshot) {
        final values = snapshot.data ?? const <Map<String, dynamic>>[];
        if (values.isEmpty) return _GenerateCard(loading: controller.isLoading);
        final latest = _metadataMix(values.first);
        if (latest == null) return _GenerateCard(loading: controller.isLoading);
        return _JourneyCard(mix: latest, continuity: {'score': latest.previousContinuityScore}, canEvolve: false, loading: controller.isLoading);
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
    if (id == null || title == null || description == null || reason == null || createdAt == null || targetMinutes == null) return null;
    return IntelligenceMix(id: id, title: title, description: description, songs: const [], targetDuration: Duration(minutes: targetMinutes), createdAt: createdAt, reason: reason, parentMixId: value['parentMixId'] as String?, edition: (value['edition'] as num?)?.toInt() ?? 1, previousContinuityScore: (value['previousContinuityScore'] as num?)?.toDouble());
  }
}

class _GenerateCard extends StatelessWidget {
  final bool loading;
  const _GenerateCard({required this.loading});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = context.read<IntelligenceMixController>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 16, 17, 15),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.auto_awesome_rounded, color: scheme.primary)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('A mix for this moment', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text('Let Deep Companion shape a listening journey from what you actually tend to keep.', style: theme.textTheme.bodyMedium)])),
          const SizedBox(width: 8),
          loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : FilledButton(onPressed: () => controller.generateMix(), child: const Text('Make mix')),
        ]),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final IntelligenceMix mix;
  final Map<String, dynamic>? continuity;
  final bool canEvolve;
  final bool loading;
  const _JourneyCard({required this.mix, this.continuity, this.canEvolve = false, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = context.read<IntelligenceMixController>();
    final music = context.read<MusicProvider>();
    final score = (continuity?['score'] as num?)?.toDouble() ?? mix.previousContinuityScore;
    final evidence = score == null ? mix.reason : score >= .65 ? 'You stayed with the previous journey, so its strongest path is being kept.' : score <= .35 ? 'The previous journey did not land as well, so this edition opens a different path.' : 'Useful signals from the previous journey are kept while making room for change.';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 16, 17, 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.auto_awesome_rounded, color: scheme.primary)), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(mix.edition > 1 ? 'Your mix has evolved' : 'Your Companion mix', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)), Text('Edition ${mix.edition}', style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary))])), if (loading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))]),
          const SizedBox(height: 11),
          Text(mix.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(evidence, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          Row(children: [Icon(Icons.library_music_outlined, size: 17, color: scheme.onSurfaceVariant), const SizedBox(width: 6), Text(mix.songs.isEmpty ? 'Remembered journey' : '${mix.songs.length} tracks'), const SizedBox(width: 14), Icon(Icons.schedule_outlined, size: 17, color: scheme.onSurfaceVariant), const SizedBox(width: 6), Text('${mix.targetDuration.inMinutes} min target')]),
          if (mix.songs.isNotEmpty) ...[
            const SizedBox(height: 11),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: loading ? null : () async { await music.playSong(mix.songs.first, queue: mix.songs, startIndex: 0); }, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play journey'))),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: loading ? null : controller.evaluateCurrentMix, icon: const Icon(Icons.insights_rounded), label: const Text('Evaluate')),
            ]),
            if (canEvolve) ...[const SizedBox(height: 8), SizedBox(width: double.infinity, child: TextButton.icon(onPressed: loading ? null : controller.evolveCurrentMix, icon: const Icon(Icons.auto_awesome_rounded), label: const Text('Evolve this journey')))],
          ] else
            Padding(padding: const EdgeInsets.only(top: 10), child: Text('Open the Player or For You again to restore this journey with its saved track order.', style: theme.textTheme.labelMedium)),
        ]),
      ),
    );
  }
}
