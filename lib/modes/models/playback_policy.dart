import 'media_type.dart';
import 'resonate_mode.dart';

enum UiDensity {
  full,
  reduced,
  minimal,
}

/// Policy emitted by the Mode Engine. Playback engines consume this policy.
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

  bool allowsMediaType(MediaType type, {bool userExplicit = false}) {
    if (userExplicit) return true;
    return !avoidedMediaTypes.contains(type);
  }

  bool prefersMediaType(MediaType type) {
    if (preferredMediaTypes.isEmpty) return true;
    return preferredMediaTypes.contains(type);
  }
}
