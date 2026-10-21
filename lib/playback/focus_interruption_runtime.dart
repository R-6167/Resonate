/// Transient audio-focus / duck state (not user prefs).
///
/// Prefs live in [AudioFocusSettings]. [MusicProvider] still owns
/// `_duckForInterruption` / `_unduckAfterInterruption` / claim-focus streams;
/// this type holds the in-flight duck flags and resume generation.
class FocusInterruptionRuntime {
  /// True while system asked us to duck (notification / nav / transient).
  bool isDucked = false;

  /// Focus returned during a crossfade; defer gain restoration until handoff ends.
  bool unduckPendingAfterCrossfade = false;

  /// When exclusive focus was lost (call / other media) — long-call gate.
  DateTime? focusLostAt;

  int resumeGeneration = 0;

  /// Invalidates an in-flight unduck only when a newer focus event arrives.
  /// Transport commands may cancel volume fades, but must not strand the
  /// engine at the temporary duck gain after focus has already returned.
  int focusEventGeneration = 0;

  int noteFocusEvent() => ++focusEventGeneration;

  bool ownsFocusEventGeneration(int generation) =>
      focusEventGeneration == generation;

  static const double duckLevel = 0.32;
  static const int duckFadeMs = 180;
  static const Duration autoResumeMaxFocusLoss = Duration(minutes: 3);

  int bumpResumeGeneration() => ++resumeGeneration;

  bool ownsResumeGeneration(int generation) => resumeGeneration == generation;

  void markFocusLost([DateTime? at]) {
    focusLostAt = at ?? DateTime.now();
  }

  void clearFocusLost() {
    focusLostAt = null;
  }

  /// Whether auto-resume is still allowed after a focus loss of this duration.
  bool mayAutoResume([DateTime? now]) {
    final lost = focusLostAt;
    if (lost == null) return true;
    final n = now ?? DateTime.now();
    return n.difference(lost) <= autoResumeMaxFocusLoss;
  }

  void markDucked() {
    isDucked = true;
  }

  void clearDucked() {
    isDucked = false;
  }

  void requestUnduckAfterCrossfade() {
    unduckPendingAfterCrossfade = true;
  }

  void clearUnduckPending() {
    unduckPendingAfterCrossfade = false;
  }
}
