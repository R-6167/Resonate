import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/queue_snapshot_store.dart';
import '../ui/resonate_glass.dart';
import '../widgets/dj_mode_status_chip.dart';
import 'player_screen.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final _snapshotStore = QueueSnapshotStore();
  bool _hasLastQueue = false;

  @override
  void initState() {
    super.initState();
    _refreshSnapshotFlag();
  }

  Future<void> _refreshSnapshotFlag() async {
    final has = await _snapshotStore.hasSnapshot();
    if (mounted) setState(() => _hasLastQueue = has);
  }

  Future<void> _saveQueueAsPlaylist(MusicProvider music) async {
    final queue = music.queue;
    if (queue.isEmpty) return;
    final nameCtrl = TextEditingController(
      text: 'Queue ${DateTime.now().month}/${DateTime.now().day}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save queue as playlist'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Playlist name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || name.isEmpty || !mounted) return;

    final playlists = context.read<PlaylistProvider>();
    final created = await playlists.createPlaylist(name, description: 'Saved from queue');
    if (created == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create playlist.')),
      );
      return;
    }
    await playlists.addSongs(created.id, List<Song>.from(queue));
    await _snapshotStore.save(queue, music.queueIndex);
    await _refreshSnapshotFlag();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${queue.length} tracks to "$name"')),
    );
  }

  Future<void> _snapshotCurrentQueue(MusicProvider music) async {
    if (music.queue.isEmpty) return;
    await _snapshotStore.save(music.queue, music.queueIndex);
    await _refreshSnapshotFlag();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Queue saved for restore')),
    );
  }

  Future<void> _restoreLastQueue(MusicProvider music) async {
    final snap = await _snapshotStore.load();
    if (snap == null || snap.ids.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No saved queue found.')),
        );
      }
      return;
    }
    final library = context.read<LibraryProvider>();
    final byId = {for (final s in library.allSongs) s.id: s};
    final restored = <Song>[];
    for (final id in snap.ids) {
      final song = byId[id];
      if (song != null) restored.add(song);
    }
    if (restored.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved queue tracks are no longer in the library.')),
        );
      }
      return;
    }
    final start = snap.index.clamp(0, restored.length - 1);
    final ok = await music.playSong(
      restored[start],
      queue: restored,
      startIndex: start,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Restored ${restored.length} tracks'
              : 'Restored queue but could not start playback',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResonateGlassScaffold(
      title: const Text('Queue'),
      actions: [
        Consumer<MusicProvider>(
          builder: (context, music, _) {
            return PopupMenuButton<String>(
              tooltip: 'Queue actions',
              onSelected: (value) async {
                switch (value) {
                  case 'save_playlist':
                    await _saveQueueAsPlaylist(music);
                  case 'snapshot':
                    await _snapshotCurrentQueue(music);
                  case 'restore':
                    await _restoreLastQueue(music);
                  case 'clear_upcoming':
                    final upcoming = music.queue.length - music.queueIndex - 1;
                    if (upcoming <= 0) return;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear upcoming?'),
                        content: Text(
                          'Remove $upcoming track${upcoming == 1 ? '' : 's'} after the current song.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                        ],
                      ),
                    );
                    if (ok == true) music.clearUpcomingQueue();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'save_playlist',
                  enabled: music.queue.isNotEmpty,
                  child: const Text('Save as playlist'),
                ),
                PopupMenuItem(
                  value: 'snapshot',
                  enabled: music.queue.isNotEmpty,
                  child: const Text('Remember this queue'),
                ),
                PopupMenuItem(
                  value: 'restore',
                  enabled: _hasLastQueue,
                  child: const Text('Restore last queue'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'clear_upcoming',
                  enabled: music.queue.length - music.queueIndex - 1 > 0,
                  child: const Text('Clear upcoming'),
                ),
              ],
            );
          },
        ),
      ],
      body: Consumer<MusicProvider>(
        builder: (context, music, _) {
          if (music.currentSong == null && music.queue.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Nothing in the queue.'),
                  if (_hasLastQueue) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => _restoreLastQueue(music),
                      child: const Text('Restore last queue'),
                    ),
                  ],
                ],
              ),
            );
          }
          final queue = music.queue;
          final currentIndex =
              music.queueIndex.clamp(0, queue.isEmpty ? 0 : queue.length - 1);

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: DjModeStatusBanner(
                  contextLabel:
                      'Next handoff may beat-align and adjust crossfade length.',
                ),
              ),
              if (music.currentSong != null)
                Material(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
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
                          ? Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.35)
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
                                    : (isPast
                                        ? Icons.history_rounded
                                        : Icons.queue_music_rounded),
                              ),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isPast
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          isCurrent
                              ? 'Now playing • ${song.artist}'
                              : song.artist,
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
                              MaterialPageRoute(
                                builder: (_) => const PlayerScreen(),
                              ),
                            );
                            return;
                          }
                          final ok = await music.playQueueIndex(index);
                          if (!context.mounted) return;
                          if (ok) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PlayerScreen(),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not play that track.'),
                              ),
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
