import '../models/song.dart';
import 'media3_playback_client.dart';

/// The transport/state contract a playback engine must provide to Resonate.
///
/// This intentionally excludes engine-specific DSP, session IDs, and
/// crossfade orchestration. Those responsibilities must be migrated as a
/// coordinated unit before MusicProvider can switch its production authority.
abstract interface class PlaybackBackend {
  Stream<Media3PlaybackState> get states;

  Future<void> loadQueue(List<Song> songs, {int startIndex = 0});
  Future<Media3PlaybackState> currentState();

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> setVolume(double value);
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode);
}

/// Repeat behavior shared by backend implementations.
enum PlaybackQueueRepeatMode {
  off('off'),
  one('one'),
  all('all');

  const PlaybackQueueRepeatMode(this.nativeValue);

  final String nativeValue;
}