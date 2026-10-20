import '../modes/models/playback_policy.dart';

/// Pure interpretation of Mode policy for Autopilot.
///
/// This class decides what Autopilot may prefer; it never performs playback,
/// queue mutation, or consent changes. MusicProvider remains authoritative.
class AutopilotModePolicy {
  const AutopilotModePolicy._();

  /// Playback mutation is allowed only while all three independent gates are
  /// still open. Keep this pure so consent races can be regression-tested.
  static bool mayMutatePlayback({
    required bool consentGranted,
    required bool intelligenceEnabled,
    required bool autopilotEnabled,
  }) =>
      consentGranted && intelligenceEnabled && autopilotEnabled;

  static bool allowsAutomaticNext(PlaybackPolicy? policy) =>
      policy?.autoNextPreferred != false;

  static bool shouldUseCrossfade({
    required bool userCrossfadeEnabled,
    PlaybackPolicy? policy,
  }) =>
      userCrossfadeEnabled &&
      (policy?.preferCrossfade ?? true) &&
      (policy?.crossfadeAllowed ?? true);

  static int predictedSequenceCount(PlaybackPolicy? policy) =>
      policy?.preferLongSessions == true ? 4 : 2;
}
