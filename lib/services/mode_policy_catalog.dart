import '../models/media_type.dart';
import '../models/playback_policy.dart';
import '../models/resonate_mode.dart';

/// Static policy table for each [ResonateMode].
/// Modes configure engines; they never own a second playback implementation.
class ModePolicyCatalog {
  ModePolicyCatalog._();

  static PlaybackPolicy policyFor(ResonateMode mode) {
    switch (mode) {
      case ResonateMode.normal:
        return const PlaybackPolicy(
          mode: ResonateMode.normal,
          crossfadeAllowed: true,
          preferCrossfade: true,
          autoNextPreferred: true,
          shuffleAllowed: true,
          preciseResume: false,
          speedControlsEmphasized: false,
          sleepTimerSuggested: false,
          chapterAwareNavigation: false,
          uiDensity: UiDensity.full,
          hideAdvancedSettingsEntry: false,
          preferredMediaTypes: {},
          avoidedMediaTypes: {},
          automationElevated: false,
          preferLongSessions: false,
        );
      case ResonateMode.running:
        return const PlaybackPolicy(
          mode: ResonateMode.running,
          crossfadeAllowed: true,
          preferCrossfade: true,
          autoNextPreferred: true,
          shuffleAllowed: true,
          preciseResume: false,
          speedControlsEmphasized: false,
          sleepTimerSuggested: false,
          chapterAwareNavigation: false,
          uiDensity: UiDensity.reduced,
          hideAdvancedSettingsEntry: true,
          preferredMediaTypes: {MediaType.music},
          avoidedMediaTypes: {
            MediaType.podcast,
            MediaType.audiobook,
          },
          automationElevated: true,
          preferLongSessions: false,
        );
      case ResonateMode.driving:
        return const PlaybackPolicy(
          mode: ResonateMode.driving,
          crossfadeAllowed: true,
          preferCrossfade: true,
          autoNextPreferred: true,
          shuffleAllowed: true,
          preciseResume: false,
          speedControlsEmphasized: false,
          sleepTimerSuggested: false,
          chapterAwareNavigation: false,
          uiDensity: UiDensity.minimal,
          hideAdvancedSettingsEntry: true,
          preferredMediaTypes: {MediaType.music},
          avoidedMediaTypes: {
            MediaType.podcast,
            MediaType.audiobook,
          },
          automationElevated: true,
          preferLongSessions: true,
        );
      case ResonateMode.work:
        return const PlaybackPolicy(
          mode: ResonateMode.work,
          crossfadeAllowed: true,
          preferCrossfade: false,
          autoNextPreferred: true,
          shuffleAllowed: true,
          preciseResume: false,
          speedControlsEmphasized: false,
          sleepTimerSuggested: false,
          chapterAwareNavigation: false,
          uiDensity: UiDensity.reduced,
          hideAdvancedSettingsEntry: false,
          preferredMediaTypes: {MediaType.music},
          avoidedMediaTypes: {},
          automationElevated: false,
          preferLongSessions: true,
        );
      case ResonateMode.podcast:
        return const PlaybackPolicy(
          mode: ResonateMode.podcast,
          crossfadeAllowed: false,
          preferCrossfade: false,
          autoNextPreferred: true,
          shuffleAllowed: false,
          preciseResume: true,
          speedControlsEmphasized: true,
          sleepTimerSuggested: true,
          chapterAwareNavigation: false,
          uiDensity: UiDensity.reduced,
          hideAdvancedSettingsEntry: false,
          preferredMediaTypes: {MediaType.podcast},
          avoidedMediaTypes: {},
          automationElevated: false,
          preferLongSessions: true,
        );
      case ResonateMode.motivation:
        return const PlaybackPolicy(
          mode: ResonateMode.motivation,
          crossfadeAllowed: true,
          preferCrossfade: false,
          autoNextPreferred: true,
          shuffleAllowed: true,
          preciseResume: true,
          speedControlsEmphasized: true,
          sleepTimerSuggested: false,
          chapterAwareNavigation: false,
          uiDensity: UiDensity.reduced,
          hideAdvancedSettingsEntry: false,
          preferredMediaTypes: {
            MediaType.motivation,
            MediaType.music,
          },
          avoidedMediaTypes: {},
          automationElevated: false,
          preferLongSessions: false,
        );
      case ResonateMode.audiobook:
        return const PlaybackPolicy(
          mode: ResonateMode.audiobook,
          crossfadeAllowed: false,
          preferCrossfade: false,
          autoNextPreferred: true,
          shuffleAllowed: false,
          preciseResume: true,
          speedControlsEmphasized: true,
          sleepTimerSuggested: true,
          chapterAwareNavigation: true,
          uiDensity: UiDensity.reduced,
          hideAdvancedSettingsEntry: false,
          preferredMediaTypes: {MediaType.audiobook},
          avoidedMediaTypes: {},
          automationElevated: false,
          preferLongSessions: true,
        );
    }
  }
}
