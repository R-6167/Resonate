import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/listening_history_provider.dart';
import '../providers/music_provider.dart';
import '../models/song.dart';
import 'player_screen.dart';

class ListeningHistoryScreen extends StatelessWidget {
  const ListeningHistoryScreen({super.key});

  String _formatDuration(int ms) {
    final minutes = Duration(milliseconds: ms).inMinutes;
    final hours = minutes ~/ 60;
    if (hours > 0) return '${hours}h ${minutes % 60}m';
    return '${minutes}m';
  }

  Future<void> _play(BuildContext context, Song song) async {
    final music = context.read<MusicProvider>();
    if (await music.playSong(song)) {
      if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Listening History'),
      actions: [
        Consumer<ListeningHistoryProvider>(builder: (context, provider, _) => IconButton(
          tooltip: 'Clear history',
          onPressed: provider.items.isEmpty ? null : () async {
            final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
              title: const Text('Clear listening history?'),
              content: const Text('This removes listening events used by Intelligence. Your music, favorites and playlists stay untouched.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear'))],
            ));
            if (confirmed == true && context.mounted) await context.read<ListeningHistoryProvider>().clearHistory();
          },
          icon: const Icon(Icons.delete_sweep_rounded),
        )),
      ],
    ),
    body: Consumer<ListeningHistoryProvider>(builder: (context, provider, _) {
      if (provider.isLoading && provider.items.isEmpty) return const Center(child: CircularProgressIndicator());
      final stats = provider.stats;
      return RefreshIndicator(
        onRefresh: provider.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _Stat(label: 'Sessions', value: '${stats['events'] ?? 0}'),
              _Stat(label: 'Completed', value: '${stats['completed'] ?? 0}'),
              _Stat(label: 'Skipped', value: '${stats['skipped'] ?? 0}'),
              _Stat(label: 'Time', value: _formatDuration((stats['playedMs'] as num?)?.toInt() ?? 0)),
            ]))),
            const SizedBox(height: 14),
            Text('Recent listening', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            if (provider.items.isEmpty)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('Nothing here yet. Start listening and Resonate will build your local history.'))),
            ...provider.items.map((item) {
              final song = item.song;
              final event = item.event;
              final title = song?.title ?? 'Song no longer in library';
              final artist = song?.artist ?? 'Unavailable';
              final status = event.completed ? 'Completed' : event.skipped ? 'Skipped' : 'Played';
              final when = _relative(event.startedAt);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 2),
                leading: CircleAvatar(child: Icon(event.completed ? Icons.check_rounded : event.skipped ? Icons.fast_forward_rounded : Icons.music_note_rounded)),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('$artist • $status • $when', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: song == null ? null : IconButton(icon: const Icon(Icons.play_arrow_rounded), tooltip: 'Play', onPressed: () => _play(context, song)),
              );
            }),
          ],
        ),
      );
    }),
  );

  static String _relative(DateTime value) {
    final delta = DateTime.now().difference(value);
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override Widget build(BuildContext context) => Column(children: [Text(value, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 2), Text(label, style: Theme.of(context).textTheme.bodySmall)]);
}
