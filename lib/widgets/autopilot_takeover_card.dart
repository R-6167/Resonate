import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/autopilot_controller.dart';
import '../providers/music_provider.dart';

class AutopilotTakeoverCard extends StatelessWidget {
  const AutopilotTakeoverCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AutopilotController>();
    if (!controller.hasPendingTakeover) return const SizedBox.shrink();

    final music = context.read<MusicProvider>();
    final song = music.queue.where((item) => item.id == controller.pendingSongId).cast<dynamic>().firstOrNull;
    if (song == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Card(
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
                  Text('Next: ${song.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                  Text('I chose this from your listening pattern.', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            TextButton(onPressed: controller.denyPendingTakeover, child: const Text('Keep current')),
            FilledButton(onPressed: controller.allowPendingTakeover, child: const Text('Let it choose')),
          ],
        ),
      ),
    );
  }
}
