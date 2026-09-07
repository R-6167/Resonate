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
      if (music.currentSong == null) return const Center(child: Text('Nothing is playing.'));
      final played = music.queue.take(music.queueIndex).toList();
      final upcoming = music.upcomingQueue;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Card(child: ListTile(
            leading: const Icon(Icons.play_circle_fill_rounded),
            title: const Text('Now playing'),
            subtitle: Text(music.currentSong!.title),
            trailing: Text('${music.queueIndex + 1}/${music.queue.length}'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())),
          )),
          if (played.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('Played', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            ...played.asMap().entries.map((entry) => Card(
              child: ListTile(
                enabled: false,
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: Text(entry.value.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(entry.value.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            )),
          ],
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('Up next', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('No upcoming songs. Add songs from your library or let Autopilot choose.')),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: upcoming.length,
              onReorder: (oldIndex, newIndex) async {
                await music.reorderQueue(music.queueIndex + 1 + oldIndex, music.queueIndex + 1 + newIndex);
              },
              itemBuilder: (context, index) {
                final song = upcoming[index];
                final absoluteIndex = music.queueIndex + 1 + index;
                return Card(key: ValueKey('${song.id}-$absoluteIndex'), child: ListTile(
                  leading: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle_rounded)),
                  title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(tooltip: 'Remove from queue', icon: const Icon(Icons.close_rounded), onPressed: () => music.removeFromQueue(absoluteIndex)),
                ));
              },
            ),
        ],
      );
    }),
  );
}
