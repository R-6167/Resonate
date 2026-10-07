import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../modes/integration/resonate_mode_ports.dart';
import '../modes/models/resonate_mode.dart';
import '../modes/providers/mode_provider.dart';
import '../modes/screens/modes_screen.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../services/mode_shelf_builder.dart';
import '../services/playback_authority.dart';
import '../ui/resonate_glass.dart';

/// Full virtual playlist for the active mode (folders + suggestions).
/// Never replaces the main library.
class ModeShelfScreen extends StatelessWidget {
  const ModeShelfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ModeProvider, LibraryProvider>(
      builder: (context, modes, library, _) {
        final shelf = ModeShelfBuilder.build(
          modes: modes,
          library: library.allSongs,
          limit: 200,
        );
        final scheme = Theme.of(context).colorScheme;

        return ResonateGlassScaffold(
          title: Text('${shelf.mode.label} shelf'),
          actions: [
            IconButton(
              tooltip: 'Modes',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<
                      void>(
                    builder: (_) => ModesScreen(
                      folderPicker: const ResonateModeFolderPickerPort(),
                    ),
                  ),
                );
              },
            ),
          ],
          body: shelf.isNormal
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Normal mode uses your full library.\n'
                      'Switch mode to build a virtual shelf from folders and matches.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : shelf.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Icon(Icons.playlist_remove_rounded,
                            size: 48, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(
                          shelf.emptyReason ?? 'Nothing on this shelf yet.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<
                                  void>(
                                builder: (_) => ModesScreen(
                                  folderPicker:
                                      const ResonateModeFolderPickerPort(),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('Add content folders'),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${shelf.tracks.length} tracks'
                                  '${shelf.folderCount > 0 ? ' · ${shelf.folderCount} folders' : ''}'
                                  '${shelf.suggestionCount > 0 ? ' · ${shelf.suggestionCount} suggested' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _playShelf(
                                  context,
                                  shelf.tracks,
                                  shuffle: false,
                                ),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Play'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () => _playShelf(
                                  context,
                                  shelf.tracks,
                                  shuffle: true,
                                ),
                                icon: const Icon(Icons.shuffle_rounded),
                                label: const Text('Shuffle'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                            children: [
                              if (shelf.fromFolders.isNotEmpty) ...[
                                _section(context, 'From your folders'),
                                ...shelf.fromFolders.map(
                                  (s) => _tile(
                                    context,
                                    s,
                                    shelf.tracks,
                                    badge: 'Folder',
                                  ),
                                ),
                              ],
                              if (shelf.fromClassifier.isNotEmpty) ...[
                                _section(context, 'Suggested for this mode'),
                                ...shelf.fromClassifier.map(
                                  (s) => _tile(
                                    context,
                                    s,
                                    shelf.tracks,
                                    badge: 'Suggested',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
        );
      },
    );
  }

  static Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  static Widget _tile(
    BuildContext context,
    Song song,
    List<Song> queue, {
    required String badge,
  }) {
    return ResonateGlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      child: ListTile(
        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${song.artist} · $badge',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: () {
            final idx = queue.indexWhere((x) => x.id == song.id);
            _playShelf(context, queue, startIndex: idx < 0 ? 0 : idx);
          },
        ),
        onTap: () {
          final idx = queue.indexWhere((x) => x.id == song.id);
          _playShelf(context, queue, startIndex: idx < 0 ? 0 : idx);
        },
      ),
    );
  }

  static void _playShelf(
    BuildContext context,
    List<Song> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) {
    if (tracks.isEmpty) return;
    final music = context.read<MusicProvider>();
    var queue = List<Song>.from(tracks);
    var index = startIndex.clamp(0, queue.length - 1);
    if (shuffle && queue.length > 1) {
      final first = queue[index];
      queue.shuffle();
      index = queue.indexWhere((s) => s.id == first.id);
      if (index < 0) index = 0;
    }
    PlaybackAuthority.instance.markExternalUserCommand(
      'mode_shelf',
      shuffle ? 'shuffle_play' : 'play',
    );
    unawaited(
      music.playSong(
        queue[index],
        queue: queue,
        startIndex: index,
      ),
    );
  }
}
