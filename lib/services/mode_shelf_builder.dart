import '../models/song.dart';
import '../modes/models/media_type.dart';
import '../modes/models/mode_media_item.dart';
import '../modes/models/resonate_mode.dart';
import '../modes/providers/mode_provider.dart';
import '../modes/services/media_folder_router.dart';

/// Virtual shelf for the active mode — never filters the main library.
class ModeShelf {
  const ModeShelf({
    required this.mode,
    required this.fromFolders,
    required this.fromClassifier,
    required this.fromIntelligence,
    required this.emptyReason,
  });

  final ResonateMode mode;
  final List<Song> fromFolders;
  final List<Song> fromClassifier;
  final List<Song> fromIntelligence;
  final String? emptyReason;

  List<Song> get tracks {
    final seen = <String>{};
    final out = <Song>[];
    for (final s in [...fromFolders, ...fromClassifier, ...fromIntelligence]) {
      if (seen.add(s.id)) out.add(s);
    }
    return out;
  }

  bool get isEmpty => tracks.isEmpty;
  int get folderCount => fromFolders.length;
  int get suggestionCount => fromClassifier.length + fromIntelligence.length;
  int get intelligenceCount => fromIntelligence.length;
  bool get isNormal => mode == ResonateMode.normal;
}

class ModeShelfBuilder {
  ModeShelfBuilder._();

  static ModeShelf build({
    required ModeProvider modes,
    required List<Song> library,
    List<Song> intelligenceSongs = const [],
    int limit = 80,
  }) {
    final mode = modes.mode;
    if (mode == ResonateMode.normal) {
      return const ModeShelf(
        mode: ResonateMode.normal,
        fromFolders: [],
        fromClassifier: [],
        fromIntelligence: [],
        emptyReason: 'Normal mode uses your full library.',
      );
    }

    if (library.isEmpty) {
      return ModeShelf(
        mode: mode,
        fromFolders: const [],
        fromClassifier: const [],
        fromIntelligence: const [],
        emptyReason: 'Library is empty — scan or add music first.',
      );
    }

    final preferred = modes.policy.preferredMediaTypes;
    final folderTypes =
        preferred.isEmpty ? MediaFolderStoreSupported.types : preferred;

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

      if (router.typeForPath(path) != null) {
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

      if (preferred.isEmpty) {
        fromClassifier.add(song);
        continue;
      }

      if (modes.isPreferredContent(item)) {
        fromClassifier.add(song);
      }
    }

    if (preferred.isEmpty && fromClassifier.isNotEmpty) {
      fromClassifier.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    }

    final folderIds = fromFolders.map((s) => s.id).toSet();
    final classIds = fromClassifier.map((s) => s.id).toSet();
    final fromIntel = <Song>[];
    for (final song in intelligenceSongs) {
      if (folderIds.contains(song.id) || classIds.contains(song.id)) continue;
      final path = song.filePath.trim();
      if (path.isEmpty) continue;
      final item = ModeMediaItem(
        id: song.id,
        filePath: path,
        title: song.title,
        album: song.album,
        artist: song.artist,
      );
      if (!modes.isAcceptableForAutopilot(item)) continue;
      if (preferred.isNotEmpty && !modes.isPreferredContent(item)) continue;
      fromIntel.add(song);
    }

    final folderCap = fromFolders.take(limit).toList(growable: false);
    var remain = (limit - folderCap.length).clamp(0, limit);
    final classCap = fromClassifier.take(remain).toList(growable: false);
    remain = (limit - folderCap.length - classCap.length).clamp(0, limit);
    final intelCap = fromIntel.take(remain).toList(growable: false);

    String? reason;
    if (folderCap.isEmpty && classCap.isEmpty && intelCap.isEmpty) {
      reason = folderMap.isEmpty
          ? 'No content folders for ${mode.label} yet. Add folders under Modes.'
          : 'No tracks from ${mode.label} folders are in the library yet.';
    }

    return ModeShelf(
      mode: mode,
      fromFolders: folderCap,
      fromClassifier: classCap,
      fromIntelligence: intelCap,
      emptyReason: reason,
    );
  }

  static String? membershipBadge({
    required ModeProvider modes,
    required Song song,
    required List<Song> library,
    List<Song> intelligenceSongs = const [],
  }) {
    if (modes.mode == ResonateMode.normal) return null;
    final shelf = build(
      modes: modes,
      library: library,
      intelligenceSongs: intelligenceSongs,
      limit: 300,
    );
    if (shelf.fromFolders.any((s) => s.id == song.id)) {
      return '${modes.mode.label} folder';
    }
    if (shelf.fromClassifier.any((s) => s.id == song.id) ||
        shelf.fromIntelligence.any((s) => s.id == song.id)) {
      return modes.mode.label;
    }
    return null;
  }
}

abstract final class MediaFolderStoreSupported {
  static const types = <MediaType>[
    MediaType.podcast,
    MediaType.audiobook,
    MediaType.motivation,
  ];
}
