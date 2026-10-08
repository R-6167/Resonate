import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/modes/models/media_type.dart';
import 'package:resonate/modes/models/playback_policy.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/services/mode_policy_catalog.dart';
import 'package:resonate/services/autopilot_mode_policy.dart';

void main() {
  test('Autopilot keeps automatic next enabled for every current mode', () {
    for (final mode in ResonateMode.values) {
      final policy = ModePolicyCatalog.policyFor(mode);
      expect(AutopilotModePolicy.allowsAutomaticNext(policy), isTrue,
          reason: '$mode currently permits automatic next-track behavior');
    }
    expect(AutopilotModePolicy.allowsAutomaticNext(null), isTrue);
  });

  test('Autopilot crossfade requires both user preference and Mode policy', () {
    final normal = ModePolicyCatalog.policyFor(ResonateMode.normal);
    final podcast = ModePolicyCatalog.policyFor(ResonateMode.podcast);
    final work = ModePolicyCatalog.policyFor(ResonateMode.work);

    expect(AutopilotModePolicy.shouldUseCrossfade(userCrossfadeEnabled: false, policy: normal), isFalse);
    expect(AutopilotModePolicy.shouldUseCrossfade(userCrossfadeEnabled: true, policy: normal), isTrue);
    expect(AutopilotModePolicy.shouldUseCrossfade(userCrossfadeEnabled: true, policy: podcast), isFalse);
    expect(AutopilotModePolicy.shouldUseCrossfade(userCrossfadeEnabled: true, policy: work), isFalse);

    const custom = PlaybackPolicy(
      mode: ResonateMode.work,
      crossfadeAllowed: true,
      preferCrossfade: true,
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
      preferLongSessions: false,
    );
    expect(AutopilotModePolicy.shouldUseCrossfade(userCrossfadeEnabled: true, policy: custom), isTrue);
  });

  test('Autopilot uses longer prediction sequences only when Mode requests them', () {
    expect(AutopilotModePolicy.predictedSequenceCount(
      ModePolicyCatalog.policyFor(ResonateMode.driving),
    ), 4);
    expect(AutopilotModePolicy.predictedSequenceCount(
      ModePolicyCatalog.policyFor(ResonateMode.work),
    ), 4);
    expect(AutopilotModePolicy.predictedSequenceCount(
      ModePolicyCatalog.policyFor(ResonateMode.running),
    ), 2);
    expect(AutopilotModePolicy.predictedSequenceCount(null), 2);
  });

  test('Autopilot policy contains no playback authority', () {
    expect(AutopilotModePolicy.predictedSequenceCount(
      ModePolicyCatalog.policyFor(ResonateMode.audiobook),
    ), 4);
    // The extracted boundary only returns decisions; MusicProvider still
    // owns queue mutation, playback, and transition authority.
  });
}
