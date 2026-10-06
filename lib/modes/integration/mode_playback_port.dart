/// Playback surface Modes may influence. Host enforces focus/pause authority.
abstract class ModePlaybackPort {
  /// Apply a soft content / transition bias; must not force resume over user pause.
  Future<void> applyPlaybackPolicy(Map<String, Object?> policy);
}
