import 'package:flutter/material.dart';
import '../../screens/mode_shelf_screen.dart';
import 'package:provider/provider.dart';

import '../integration/mode_folder_picker_port.dart';
import '../models/media_type.dart';
import '../models/playback_policy.dart';
import '../models/resonate_mode.dart';
import '../providers/mode_provider.dart';

/// Reference UI for the standalone Modes module.
///
/// The host app can provide a real platform folder picker through
/// [folderPicker]. Modes itself remains platform-agnostic.
class ModesScreen extends StatelessWidget {
  final ModeFolderPickerPort? folderPicker;

  const ModesScreen({super.key, this.folderPicker});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resonate Modes')),
      body: Consumer<ModeProvider>(
        builder: (context, modes, _) {
          final active = modes.mode;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Modes change how Resonate behaves — not just what plays.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('Active: ${active.emoji} ${active.label}'),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                title: const Text('Auto-enter Driving in the car'),
                subtitle: const Text(
                  'Switch automatically when car context is detected.',
                ),
                value: modes.autoEnterDrivingOnCar,
                onChanged: modes.setAutoEnterDrivingOnCar,
              ),
              const Divider(),
              for (final mode in ResonateMode.values)
                ListTile(
                  leading: Text(
                    mode.emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(mode.label),
                  subtitle: Text(mode.shortDescription),
                  trailing: active == mode
                      ? const Icon(Icons.check_circle)
                      : const Icon(Icons.circle_outlined),
                  onTap: () => modes.setMode(mode),
                ),
              const Divider(),
              _buildContentFolders(context, modes),
              const Divider(),
              Text(_policySummary(modes.policy)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContentFolders(BuildContext context, ModeProvider modes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.playlist_play_rounded),
          title: const Text('Mode shelf'),
          subtitle: const Text(
            'Virtual playlist from folders and mode matches — does not hide your library',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ModeShelfScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Content folders',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'Optional. Selected folders are treated as the chosen content type. '
          'Automatic classification is still used elsewhere.',
        ),
        const SizedBox(height: 12),
        for (final type in _folderTypes) _folderGroup(context, modes, type),
      ],
    );
  }

  Widget _folderGroup(
    BuildContext context,
    ModeProvider modes,
    MediaType type,
  ) {
    final folders = modes.foldersFor(type);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(_iconFor(type)),
            title: Text(_labelFor(type)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  folders.isEmpty
                      ? 'No folder selected'
                      : '${folders.length} folder${folders.length == 1 ? '' : 's'} selected',
                ),
                if (folders.isNotEmpty)
                  Text('${modes.folderSongCountFor(type)} audio files found'),
                if (modes.folderScanErrorFor(type) != null)
                  Text(
                    'Folder scan failed: ${modes.folderScanErrorFor(type)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            trailing: folderPicker == null
                ? null
                : IconButton(
                    tooltip: 'Add folder',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: () async {
                      final path = await folderPicker!.pickFolder(type);
                      if (path != null && path.trim().isNotEmpty) {
                        await modes.addMediaFolder(type, path);
                      }
                    },
                  ),
          ),
          for (final path in folders)
            ListTile(
              dense: true,
              title: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Remove folder',
                icon: const Icon(Icons.close),
                onPressed: () => modes.removeMediaFolder(type, path),
              ),
            ),
        ],
      ),
    );
  }

  String _labelFor(MediaType type) => switch (type) {
        MediaType.podcast => 'Podcast',
        MediaType.motivation => 'Motivation',
        MediaType.audiobook => 'Audiobook',
        _ => type.label,
      };

  IconData _iconFor(MediaType type) => switch (type) {
        MediaType.podcast => Icons.podcasts_outlined,
        MediaType.motivation => Icons.record_voice_over_outlined,
        MediaType.audiobook => Icons.menu_book_outlined,
        _ => Icons.folder_outlined,
      };

  String _policySummary(PlaybackPolicy p) {
    final density = switch (p.uiDensity) {
      UiDensity.full => 'Full UI',
      UiDensity.reduced => 'Reduced UI',
      UiDensity.minimal => 'Minimal UI',
    };
    return [
      p.crossfadeAllowed ? 'Crossfade allowed' : 'Crossfade off',
      p.preciseResume ? 'Precise resume' : 'Standard resume',
      density,
      if (p.automationElevated) 'Elevated automation',
      if (p.preferLongSessions) 'Long sessions',
    ].join(' · ');
  }
}

const _folderTypes = <MediaType>[
  MediaType.podcast,
  MediaType.motivation,
  MediaType.audiobook,
];
