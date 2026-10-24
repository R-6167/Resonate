import 'dart:async';

import '../models/song.dart';
import 'media3_playback_client.dart';

/// Provider-facing command/state facade for the native Media3 session.
///
/// This class deliberately owns no player objects and no UI state. It converts
/// Resonate's Song/queue model into immutable Media3 descriptors and forwards
/// the native state stream. MusicProvider can migrate its transport boundary
/// through this facade without exposing Media3 implementation details.
class Media3MusicProviderAdapter {
  Media3MusicProviderAdapter({Media3PlaybackClient? client})
      : _client = client ?? Media3PlaybackClient();

  final Media3PlaybackClient _client;

  Stream<Media3PlaybackState> get states => _client.states;

  Future<void> loadQueue(List<Song> songs, {int startIndex = 0}) async {
    final resolvedStartIndex = resolvePlayableStartIndex(songs, startIndex);
    final playable = songs
        .where((song) => song.filePath.trim().isNotEmpty)
        .toList(growable: false);
    await _client.setQueue(
      playable.map(Media3QueueItem.fromSong).toList(growable: false),
      startIndex: resolvedStartIndex,
    );
  }

  /// Maps an original Resonate queue index into the filtered native queue.
  /// A selected unplayable song is rejected instead of silently starting a
  /// different track.
  static int resolvePlayableStartIndex(List<Song> songs, int startIndex) {
    if (startIndex < 0 || startIndex >= songs.length) {
      throw ArgumentError.value(startIndex, 'startIndex', 'Must identify an item in the original queue.');
    }
    if (songs[startIndex].filePath.trim().isEmpty) {
      throw ArgumentError.value(startIndex, 'startIndex', 'The selected queue item is not playable.');
    }
    if (!songs.any((song) => song.filePath.trim().isNotEmpty)) {
      throw ArgumentError.value(songs, 'songs', 'Queue contains no playable tracks.');
    }
    return songs
        .take(startIndex)
        .where((song) => song.filePath.trim().isNotEmpty)
        .length;
  }

  /// Maps a native playable-queue index back to Resonate's original queue.
  /// Returns null for an invalid native index; callers must not guess a track.
  static int? resolveOriginalQueueIndex(List<Song> songs, int playableIndex) {
    if (playableIndex < 0) return null;
    var nativeIndex = 0;
    for (var originalIndex = 0; originalIndex < songs.length; originalIndex++) {
      if (songs[originalIndex].filePath.trim().isEmpty) continue;
      if (nativeIndex == playableIndex) return originalIndex;
      nativeIndex++;
    }
    return null;
  }

  /// Resolves the original queue occurrence represented by a native snapshot.
  ///
  /// Media IDs are authoritative when present. The native index disambiguates
  /// repeated occurrences of the same song; a unique ID can recover from a
  /// stale index. If an ID is present but cannot be reconciled, return null
  /// rather than silently binding state to a different song.
  static int? resolveCurrentQueueIndex(
    List<Song> originalQueue, {
    required String? mediaId,
    required int playableIndex,
  }) {
    final indexedOriginal = resolveOriginalQueueIndex(originalQueue, playableIndex);
    final hasMediaId = mediaId != null && mediaId.isNotEmpty;

    if (!hasMediaId) return indexedOriginal;

    if (indexedOriginal != null && originalQueue[indexedOriginal].id == mediaId) {
      return indexedOriginal;
    }

    int? uniqueMatch;
    for (var i = 0; i < originalQueue.length; i++) {
      final song = originalQueue[i];
      if (song.filePath.trim().isEmpty || song.id != mediaId) continue;
      if (uniqueMatch != null) return null;
      uniqueMatch = i;
    }
    return uniqueMatch;
  }

  /// Resolves native state by stable media ID and queue occurrence.
  static Song? resolveCurrentSong(
    List<Song> originalQueue, {
    required String? mediaId,
    required int playableIndex,
  }) {
    final originalIndex = resolveCurrentQueueIndex(
      originalQueue,
      mediaId: mediaId,
      playableIndex: playableIndex,
    );
    if (originalIndex == null) return null;
    return originalQueue[originalIndex];
  }

  Future<void> play() => _client.play();
  Future<void> pause() => _client.pause();
  Future<void> stop() => _client.stop();
  Future<void> seek(Duration position) => _client.seekTo(position);
  Future<void> next() => _client.skipToNext();
  Future<void> previous() => _client.skipToPrevious();
  Future<void> setVolume(double value) => _client.setVolume(value);

  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode) =>
      _client.setRepeatMode(mode.nativeValue);

  Future<Media3PlaybackState> currentState() => _client.getState();

  static Uri sourceUriForPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Media path must not be empty.');
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return parsed;
    return Uri.file(trimmed);
  }

  static Uri? artworkUriForPath(String? path) {
    final trimmed = path?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return parsed;
    return Uri.file(trimmed);
  }
}

enum PlaybackQueueRepeatMode {
  off('off'),
  one('one'),
  all('all');

  const PlaybackQueueRepeatMode(this.nativeValue);
  final String nativeValue;
}