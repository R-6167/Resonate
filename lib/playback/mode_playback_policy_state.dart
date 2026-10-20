/// Runtime snapshot of the soft playback gates supplied by Modes.
///
/// This state does not own user preferences or perform player operations;
/// MusicProvider remains responsible for enforcing the gates and synchronizing
/// native playback at mode boundaries.
class ModePlaybackPolicyState {
  bool crossfadeAllowed = true;
  bool shuffleAllowed = true;
  bool preciseResume = false;

  /// Applies a new mode policy and reports whether any gate changed.
  bool update({
    required bool crossfadeAllowed,
    required bool shuffleAllowed,
    required bool preciseResume,
  }) {
    final changed = this.crossfadeAllowed != crossfadeAllowed ||
        this.shuffleAllowed != shuffleAllowed ||
        this.preciseResume != preciseResume;
    this.crossfadeAllowed = crossfadeAllowed;
    this.shuffleAllowed = shuffleAllowed;
    this.preciseResume = preciseResume;
    return changed;
  }
}
