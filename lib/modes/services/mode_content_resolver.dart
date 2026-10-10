import '../../models/song.dart';
import '../models/mode_media_item.dart';
import '../models/resonate_mode.dart';
import '../providers/mode_provider.dart';

/// Resolves content for mode-owned surfaces (shelves, generated queues and
/// Autopilot). It never mutates or filters the canonical Library.
class ModeContentResolver {
  const ModeContentResolver();

  List<Song> resolve({
    required ModeProvider modes,
    required List<Song> songs,
    int? limit,
    bool preferPreferredContent = true,
  }) {
    if (modes.mode.id == 'normal') {
      return _cap(songs, limit);
    }

    final folderTypes = modes.policy.preferredMediaTypes.isEmpty
        ? null
        : modes.policy.preferredMediaTypes;
    final candidates = <Song>[];
    final seen = <String>{};
    for (final song in [...songs, ...modes.folderSongsFor(folderTypes)]) {
      if (seen.add(song.id)) candidates.add(song);
    }
    if (candidates.isEmpty) return const <Song>[];

    final accepted = <Song>[];
    for (final song in candidates) {
      if (song.filePath.trim().isEmpty) continue;
      final item = ModeMediaItem(
        id: song.id,
        filePath: song.filePath,
        title: song.title,
        album: song.album,
        artist: song.artist,
      );
      if (modes.isAcceptableForAutopilot(item)) {
        accepted.add(song);
      }
    }

    if (!preferPreferredContent || modes.policy.preferredMediaTypes.isEmpty) {
      return _cap(accepted, limit);
    }

    final preferred = <Song>[];
    final allowed = <Song>[];
    for (final song in accepted) {
      final item = ModeMediaItem(
        id: song.id,
        filePath: song.filePath,
        title: song.title,
        album: song.album,
        artist: song.artist,
      );
      if (modes.isPreferredContent(item)) {
        preferred.add(song);
      } else {
        allowed.add(song);
      }
    }

    return _cap([...preferred, ...allowed], limit);
  }

  bool accepts(ModeProvider modes, Song song) {
    if (modes.mode.id == 'normal') return true;
    if (song.filePath.trim().isEmpty) return false;
    return modes.isAcceptableForAutopilot(ModeMediaItem(
      id: song.id,
      filePath: song.filePath,
      title: song.title,
      album: song.album,
      artist: song.artist,
    ));
  }

  List<Song> _cap(List<Song> songs, int? limit) {
    if (limit == null || limit >= songs.length) {
      return List<Song>.unmodifiable(songs);
    }
    if (limit <= 0) return const <Song>[];
    return List<Song>.unmodifiable(songs.take(limit));
  }
}
