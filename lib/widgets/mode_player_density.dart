import 'package:flutter/material.dart';

import '../modes/models/interaction_policy.dart';
import '../modes/models/playback_policy.dart';
import '../modes/models/resonate_mode.dart';
import '../modes/providers/mode_provider.dart';

/// Layout metrics derived from Modes [PlaybackPolicy] + [InteractionPolicy].
class ModePlayerDensity {
  const ModePlayerDensity({
    required this.mode,
    required this.uiDensity,
    required this.largeControls,
    required this.reducedChrome,
    required this.allowHorizontalSwipe,
    required this.artworkHeight,
    required this.transportIconSize,
    required this.playButtonSize,
    required this.playIconSize,
    required this.secondaryIconSize,
    required this.seekTrackHeight,
    required this.seekThumbRadius,
    required this.showIntelligenceCards,
    required this.showSecondaryRow,
    required this.hintLabel,
  });

  final ResonateMode mode;
  final UiDensity uiDensity;
  final bool largeControls;
  final bool reducedChrome;
  final bool allowHorizontalSwipe;
  final double artworkHeight;
  final double transportIconSize;
  final double playButtonSize;
  final double playIconSize;
  final double secondaryIconSize;
  final double seekTrackHeight;
  final double seekThumbRadius;
  final bool showIntelligenceCards;
  final bool showSecondaryRow;
  final String? hintLabel;

  factory ModePlayerDensity.fromMode(ModeProvider modes) {
    final policy = modes.policy;
    final interaction = modes.interactionPolicy;
    final large = interaction.largeControls;
    final reduced = interaction.reducedControlCount;
    final minimal = policy.uiDensity == UiDensity.minimal;
    final drivingOrRunning = modes.mode == ResonateMode.driving ||
        modes.mode == ResonateMode.running;

    return ModePlayerDensity(
      mode: modes.mode,
      uiDensity: policy.uiDensity,
      largeControls: large,
      reducedChrome: reduced || minimal,
      allowHorizontalSwipe: interaction.allowHorizontalSwipeNavigation,
      artworkHeight: large ? 200 : 250,
      transportIconSize: large ? 42 : 30,
      playButtonSize: large ? 92 : 72,
      playIconSize: large ? 48 : 36,
      secondaryIconSize: large ? 28 : 24,
      seekTrackHeight: large ? 6 : 3,
      seekThumbRadius: large ? 12 : 8,
      // Driving/Running: less distraction on the road / while moving
      showIntelligenceCards: !drivingOrRunning && !minimal,
      showSecondaryRow: !minimal,
      hintLabel: switch (modes.mode) {
        ResonateMode.driving => 'Driving · larger controls',
        ResonateMode.running => 'Running · large targets',
        ResonateMode.podcast => 'Podcast · precise resume',
        ResonateMode.audiobook => 'Audiobook · reduced chrome',
        ResonateMode.work => 'Work · calm layout',
        ResonateMode.motivation => 'Motivation',
        ResonateMode.normal => null,
      },
    );
  }
}
