/// In-flight A/B crossfade / repeat-self state (not user preferences).
///
/// User-facing prefs (enabled, duration, fade curve) stay on [MusicProvider]
/// or [CrossfadeSettings]. This type owns generation tokens and flags so
/// transport cancel can invalidate stale automatic work without touching
/// engines.
class CrossfadeRuntime {
  bool inProgress = false;
  bool automaticInFlight = false;
  bool completionAdvanceInProgress = false;
  bool completionObservedDuringCrossfade = false;
  String? completionObservedSongId;

  /// Monotonic identity for the currently-owned automatic A/B transition.
  /// User transport invalidates the previous identity so stale async work
  /// cannot clear flags or commit an engine swap after a newer command.
  int automaticTransitionGeneration = 0;

  String? preloadedNextSongId;
  bool preloadInFlight = false;

  /// Repeat-one + crossfade: seamless loop via idle engine (no queue advance).
  bool repeatSelfHandoffArmed = false;
  bool repeatSelfHandoffInFlight = false;
  int repeatSelfGeneration = 0;
  String? repeatSelfTargetSongId;

  DateTime? transitionArmedAt;
  String? lastDurationUnavailableSongId;

  bool get isLive => inProgress || automaticInFlight;

  bool get hasRepeatSelfHandoff =>
      repeatSelfHandoffArmed || repeatSelfHandoffInFlight;

  bool get hasPreload =>
      preloadInFlight || preloadedNextSongId != null;

  /// Any automatic A/B work that user transport must invalidate.
  bool get hasAutomaticWork =>
      isLive || hasPreload || hasRepeatSelfHandoff;

  int bumpAutomaticGeneration() => ++automaticTransitionGeneration;

  int bumpRepeatSelfGeneration() => ++repeatSelfGeneration;

  bool ownsAutomaticGeneration(int generation) =>
      automaticTransitionGeneration == generation;

  bool ownsRepeatSelfGeneration(int generation) =>
      repeatSelfGeneration == generation;

  void clearFlags({bool clearRepeatSelf = true}) {
    automaticInFlight = false;
    inProgress = false;
    completionAdvanceInProgress = false;
    completionObservedDuringCrossfade = false;
    completionObservedSongId = null;
    preloadedNextSongId = null;
    preloadInFlight = false;
    if (clearRepeatSelf) {
      repeatSelfHandoffArmed = false;
      repeatSelfHandoffInFlight = false;
      repeatSelfTargetSongId = null;
    }
    transitionArmedAt = null;
  }

  void clearRepeatSelf() {
    repeatSelfHandoffArmed = false;
    repeatSelfHandoffInFlight = false;
    repeatSelfTargetSongId = null;
  }

  void markDurationUnavailable(String songId) {
    lastDurationUnavailableSongId = songId;
  }

  void clearDurationUnavailable() {
    lastDurationUnavailableSongId = null;
  }
}
