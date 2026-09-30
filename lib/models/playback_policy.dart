import 'media_type.dart';
import 'resonate_mode.dart';

/// How dense the player UI should be for the active mode.
enum UiDensity {
  full,
  reduced,
  minimal,
}

/// Policy emitted by the Mode Engine. Engines read this; they do not own modes.
class PlaybackPolicy {
  final ResonateMode mode;

  /// When false, crossfade must not run (podcast / audiobook).
  final bool crossfadeAllowed;

  /// Soft preference for crossfade when allowed (Normal still respects user setting).
  final bool preferCrossfade;

  final bool autoNextPreferred;
  final bool shuffleAllowed;

  /// Prefer exact resume position (speech long-form).
  final bool preciseResume;

  final bool speedControlsEmphasized;
  final bool sleepTimerSuggested;
  final bool chapterAwareNavigation;

  final UiDensity uiDensity;
  final bool hideAdvancedSettingsEntry;

  /// Content types the mode prefers. Empty = no bias.
  final Set<MediaType> preferredMediaTypes;

  /// Content types the mode avoids unless user explicitly plays them.
  final Set<MediaType> avoidedMediaTypes;

  /// Intelligence / Autopilot may take more responsibility.
  final bool automationElevated;

  /// Prefer fewer transitions (Work).
  final bool preferLongSessions;

  const PlaybackPolicy({
    required this.mode,
    required this.crossfadeAllowed,
    required this.preferCrossfade,
    required this.autoNextPreferred,
    required this.shuffleAllowed,
    required this.preciseResume,
    required this.speedControlsEmphasized,
    required this.sleepTimerSuggested,
    required this.chapterAwareNavigation,
    required this.uiDensity,
    required this.hideAdvancedSettingsEntry,
    required this.preferredMediaTypes,
    required this.avoidedMediaTypes,
    required this.automationElevated,
    required this.preferLongSessions,
  });

  /// True when [type] is acceptable under this policy (user explicit play always ok).
  bool allowsMediaType(MediaType type, {bool userExplicit = false}) {
    if (userExplicit) return true;
    if (avoidedMediaTypes.contains(type)) return false;
    return true;
  }

  bool prefersMediaType(MediaType type) {
    if (preferredMediaTypes.isEmpty) return true;
    return preferredMediaTypes.contains(type);
  }
}
