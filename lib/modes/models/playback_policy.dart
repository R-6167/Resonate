import 'media_type.dart';
import 'resonate_mode.dart';

enum UiDensity { full, reduced, minimal }

/// Complete behavioral contract emitted by Modes.
///
/// The playback engine consumes this policy; Modes never owns playback.
class PlaybackPolicy {
  final ResonateMode mode;
  final bool crossfadeAllowed;
  final bool preferCrossfade;
  final bool autoNextPreferred;
  final bool shuffleAllowed;
  final bool preciseResume;
  final bool speedControlsEmphasized;
  final bool sleepTimerSuggested;
  final bool chapterAwareNavigation;
  final UiDensity uiDensity;
  final bool hideAdvancedSettingsEntry;
  final Set<MediaType> preferredMediaTypes;
  final Set<MediaType> avoidedMediaTypes;
  final bool automationElevated;
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

  bool allowsMediaType(MediaType type, {bool userExplicit = false}) =>
      userExplicit || !avoidedMediaTypes.contains(type);

  bool prefersMediaType(MediaType type) =>
      preferredMediaTypes.isEmpty || preferredMediaTypes.contains(type);

  /// Unknown content is never treated as preferred merely because a mode
  /// has a preferred category. It remains playable unless explicitly avoided.
  bool isUnknownNeutral(MediaType type) =>
      type == MediaType.unknown && !avoidedMediaTypes.contains(type);
}
