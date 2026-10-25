/// Engine-neutral playback state consumed by Resonate's provider and UI.
///
/// This deliberately avoids Media3/ExoPlayer types so a backend can be swapped
/// without making MusicProvider depend on a particular native engine.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.connected,
    required this.isPlaying,
    required this.isReady,
    required this.playWhenReady,
    required this.position,
    required this.duration,
    required this.mediaId,
    required this.title,
    required this.artist,
    required this.album,
    required this.currentQueueIndex,
    required this.queueLength,
    required this.volume,
    this.repeatMode = 'off',
    this.shuffleModeEnabled = false,
    required this.hasError,
    required this.error,
  });

  final bool connected;
  final bool isPlaying;
  final bool isReady;
  final bool playWhenReady;
  final Duration position;
  final Duration? duration;
  final String? mediaId;
  final String? title;
  final String? artist;
  final String? album;
  final int currentQueueIndex;
  final int queueLength;
  final double volume;
  /// Current queue repeat policy: `off`, `one`, or `all`.
  final String repeatMode;
  final bool shuffleModeEnabled;
  final bool hasError;
  final String? error;
}
