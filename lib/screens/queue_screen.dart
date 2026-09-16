import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import 'player_screen.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Queue'),
      actions: [
        Consumer<MusicProvider>(builder: (context, music, _) => IconButton(
          tooltip: 'Clear upcoming',
          onPressed: music.upcomingQueue.isEmpty ? null : music.clearUpcomingQueue,
          icon: const Icon(Icons.clear_all_rounded),
        )),
      ],
    ),
    body: Consumer<MusicProvider>(builder: (context, music, _) {
      if (music.currentSong == null && music.queue.isEmpty) {
        return const Center(child: Text('Nothing in the queue.'));
      }
      final queue = music.queue;
      final currentIndex = music.queueIndex;
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: queue.length,
        itemBuilder: (context, index) {
          final song = queue[index];
          final isCurrent = index == currentIndex;
          final isPast = index < currentIndex;
          return Card(
            color: isCurrent
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                : null,
            child: ListTile(
              leading: Icon(
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
                    : (isPast ? 'Played • tap to play again • ${song.artist}' : song.artist),
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
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
                  return;
                }
                final ok = await music.playQueueIndex(index);
                if (!context.mounted) return;
                if (ok) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not play that track.')),
                  );
                }
              },
            ),
          );
        },
      );
    }),
  );
}
