import '../models/song.dart';
import '../modes/models/media_type.dart';
import '../modes/models/mode_media_item.dart';
import '../modes/models/resonate_mode.dart';
import '../modes/providers/mode_provider.dart';
import '../modes/services/media_folder_router.dart';

/// One virtual shelf for the active listening mode.
///
/// Does **not** filter the main library. Folder matches rank first, then
/// classifier / preference matches. Failures (no folders, empty library)
/// produce an empty shelf with an honest reason — never a wiped library.
class ModeShelf {
  const ModeShelf({
    required this.mode,
    required this.fromFolders,
    required this.fromClassifier,
    required this.emptyReason,
  });

  final ResonateMode mode;
  final List<Song> fromFolders;
  final List<Song> fromClassifier;
  final String? emptyReason;

  /// Folders first, then classifier suggestions; de-duplicated by id.
  List<Song> get tracks {
    final seen = <String>{};
    final out = <Song>[];
    for (final s in [...fromFolders, ...fromClassifier]) {
      if (seen.add(s.id)) out.add(s);
    }
    return out;
  }

  bool get isEmpty => tracks.isEmpty;
  int get folderCount => fromFolders.length;
  int get suggestionCount => fromClassifier.length;

  bool get isNormal => mode == ResonateMode.normal;
}

class ModeShelfBuilder {
  ModeShelfBuilder._();

  static ModeShelf build({
    required ModeProvider modes,
    required List<Song> library,
    int limit = 80,
  }) {
    final mode = modes.mode;
    if (mode == ResonateMode.normal) {
      return const ModeShelf(
        mode: ResonateMode.normal,
        fromFolders: [],
        fromClassifier: [],
        emptyReason: 'Normal mode uses your full library.',
      );
    }

    if (library.isEmpty) {
      return ModeShelf(
        mode: mode,
        fromFolders: const [],
        fromClassifier: const [],
        emptyReason: 'Library is empty — scan or add music first.',
      );
    }

    final preferred = modes.policy.preferredMediaTypes;
    final folderTypes = preferred.isEmpty
        ? MediaFolderStoreSupported.types
        : preferred;

    // Collect folder paths for types this mode cares about.
    final folderMap = <MediaType, List<String>>{};
    for (final type in folderTypes) {
      final folders = modes.foldersFor(type);
      if (folders.isNotEmpty) folderMap[type] = folders;
    }
    final router = MediaFolderRouter(folderMap);

    final fromFolders = <Song>[];
    final fromClassifier = <Song>[];

    for (final song in library) {
      final path = song.filePath.trim();
      if (path.isEmpty) continue;

      final folderType = router.typeForPath(path);
      if (folderType != null) {
        // In a mode-linked folder → strong include
        fromFolders.add(song);
        continue;
      }

      final item = ModeMediaItem(
        id: song.id,
        filePath: path,
        title: song.title,
        album: song.album,
        artist: song.artist,
      );

      if (!modes.isAcceptableForAutopilot(item)) continue;
      if (preferred.isEmpty) continue; // music-first modes without prefs: folders only

      if (modes.isPreferredContent(item)) {
        fromClassifier.add(song);
      }
    }

    // Cap each bucket so the shelf stays snappy
    final folderCap = fromFolders.take(limit).toList(growable: false);
    final remain = (limit - folderCap.length).clamp(0, limit);
    final classCap = fromClassifier.take(remain).toList(growable: false);

    String? reason;
    if (folderCap.isEmpty && classCap.isEmpty) {
      if (folderMap.isEmpty) {
        reason =
            'No content folders for ${mode.label} yet. Add folders under Modes, or wait for library matches.';
      } else {
        reason =
            'No tracks from ${mode.label} folders are in the library yet. Re-scan or check folder paths.';
      }
    }

    return ModeShelf(
      mode: mode,
      fromFolders: folderCap,
      fromClassifier: classCap,
      emptyReason: reason,
    );
  }
}

/// Folder types Modes can assign (aligned with MediaFolderStore).
abstract final class MediaFolderStoreSupported {
  static const types = <MediaType>[
    MediaType.podcast,
    MediaType.audiobook,
    MediaType.motivation,
  ];
}
