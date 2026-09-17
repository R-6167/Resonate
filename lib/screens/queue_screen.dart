import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/music_provider.dart';
import 'player_screen.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          Consumer<MusicProvider>(
            builder: (context, music, _) {
              final upcoming = music.queue.length - music.queueIndex - 1;
              if (upcoming <= 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear upcoming?'),
                      content: Text('Remove $upcoming track${upcoming == 1 ? '' : 's'} after the current song.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                      ],
                    ),
                  );
                  if (ok == true) music.clearUpcomingQueue();
                },
                child: const Text('Clear upcoming'),
              );
            },
          ),
        ],
      ),
      body: Consumer<MusicProvider>(
        builder: (context, music, _) {
          if (music.currentSong == null && music.queue.isEmpty) {
            return const Center(child: Text('Nothing in the queue.'));
          }
          final queue = music.queue;
          final currentIndex = music.queueIndex.clamp(0, queue.isEmpty ? 0 : queue.length - 1);

          return Column(
            children: [
              if (music.currentSong != null)
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: ListTile(
                    leading: const Icon(Icons.graphic_eq_rounded),
                    title: Text(
                      music.currentSong!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Now playing • ${currentIndex + 1} of ${queue.length}'
                      '${music.shuffleEnabled ? ' • shuffle' : ''}'
                      '${music.repeatMode.name != 'off' ? ' • repeat ${music.repeatMode.name}' : ''}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Open player',
                      icon: const Icon(Icons.open_in_new_rounded),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PlayerScreen()),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: queue.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) async {
                    // Only upcoming rows are reorderable in provider; still try.
                    if (oldIndex == currentIndex) return;
                    await music.reorderQueue(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final song = queue[index];
                    final isCurrent = index == currentIndex;
                    final isPast = index < currentIndex;
                    final canReorder = index > currentIndex;

                    return Card(
                      key: ValueKey('queue_${song.id}_$index'),
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                          : null,
                      child: ListTile(
                        leading: canReorder
                            ? ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle_rounded),
                              )
                            : Icon(
                                isCurrent
                                    ? Icons.play_circle_fill_rounded
                                    : (isPast ? Icons.replay_rounded : Icons.queue_music_rounded),
                              ),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500),
                        ),
                        subtitle: Text(
                          isCurrent
                              ? 'Now playing • ${song.artist}'
                              : (isPast ? 'Played • ${song.artist}' : song.artist),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isCurrent
                            ? Text('${index + 1}/${queue.length}')
                            : IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => music.removeFromQueue(index),
                              ),
                        onTap: () async {
                          if (isCurrent) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PlayerScreen()),
                            );
                            return;
                          }
                          final ok = await music.playQueueIndex(index);
                          if (!context.mounted) return;
                          if (ok) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PlayerScreen()),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Could not play that track.')),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
