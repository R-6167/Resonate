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
    final playable = songs.where((song) => song.filePath.trim().isNotEmpty).toList(growable: false);
    if (playable.isEmpty) {
      throw ArgumentError.value(songs, 'songs', 'Queue contains no playable tracks.');
    }
    if (startIndex < 0 || startIndex >= playable.length) {
      throw ArgumentError.value(startIndex, 'startIndex', 'Must identify a playable queue item.');
    }
    await _client.setQueue(
      playable.map(Media3QueueItem.fromSong).toList(growable: false),
      startIndex: startIndex,
    );
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
