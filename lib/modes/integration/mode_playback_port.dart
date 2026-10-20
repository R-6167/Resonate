/// Adapter implemented by Resonate's real playback engine.
///
/// Modes configure playback; they do not own playback.
abstract interface class ModePlaybackPort {
  void applyModePlaybackPolicy({
    required bool crossfadeAllowed,
    required bool shuffleAllowed,
    required bool preciseResume,
  });
}
