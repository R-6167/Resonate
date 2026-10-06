import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../modes/integration/resonate_mode_ports.dart';
import '../modes/models/resonate_mode.dart';
import '../modes/providers/mode_provider.dart';
import '../modes/screens/modes_screen.dart';
import '../providers/library_provider.dart';
import '../providers/music_provider.dart';
import '../services/mode_shelf_builder.dart';
import '../services/playback_authority.dart';
import '../ui/resonate_glass.dart';

/// Home card: virtual playlist for the active mode (folders + suggestions).
/// Never replaces the main library.
class ModeShelfCard extends StatelessWidget {
  const ModeShelfCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ModeProvider, LibraryProvider>(
      builder: (context, modes, library, _) {
        if (!modes.isReady) return const SizedBox.shrink();

        final shelf = ModeShelfBuilder.build(
          modes: modes,
          library: library.allSongs,
        );

        // Normal: compact note, no faux playlist
        if (shelf.isNormal) {
          return const SizedBox.shrink();
        }

        final scheme = Theme.of(context).colorScheme;
        final tracks = shelf.tracks;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ResonateGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.playlist_play_rounded, color: scheme.tertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${shelf.mode.label} shelf',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            tracks.isEmpty
                                ? 'Virtual playlist for this mode'
                                : '${tracks.length} track${tracks.length == 1 ? '' : 's'}'
                                    '${shelf.folderCount > 0 ? ' · ${shelf.folderCount} from folders' : ''}'
                                    '${shelf.suggestionCount > 0 ? ' · ${shelf.suggestionCount} suggested' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Modes settings',
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
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (tracks.isEmpty) ...[
                  Text(
                    shelf.emptyReason ?? 'Nothing on this shelf yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
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
                ] else ...[
                  ...tracks.take(5).map(
                        (s) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.music_note_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                          title: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            s.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            final music = context.read<MusicProvider>();
                            final idx = tracks.indexWhere((x) => x.id == s.id);
                            PlaybackAuthority.instance.markExternalUserCommand(
                              'mode_shelf',
                              'play_track',
                            );
                            unawaited(music.playSong(
                              s,
                              queue: tracks,
                              startIndex: idx < 0 ? 0 : idx,
                            ));
                          },
                        ),
                      ),
                  if (tracks.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '+${tracks.length - 5} more',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          final music = context.read<MusicProvider>();
                          PlaybackAuthority.instance.markExternalUserCommand(
                            'mode_shelf',
                            'play_shelf',
                          );
                          unawaited(music.playSong(
                            tracks.first,
                            queue: tracks,
                            startIndex: 0,
                          ));
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play shelf'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final music = context.read<MusicProvider>();
                          final ok = await music.enqueueSongs(tracks);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Added ${tracks.length} track(s) to queue'
                                      : 'Nothing new to add',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.queue_music_rounded),
                        label: const Text('Queue all'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
