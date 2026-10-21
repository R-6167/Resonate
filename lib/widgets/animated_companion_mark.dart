import 'package:flutter/material.dart';

/// Lightweight companion glyph. Any movement is derived from measured audio,
/// never from an always-running idle animation.
class AnimatedCompanionMark extends StatelessWidget {
  final String mode;
  final double size;
  final double audioEnergy;

  const AnimatedCompanionMark({
    super.key,
    required this.mode,
    this.size = 28,
    this.audioEnergy = 0,
  });

  IconData get _icon => switch (mode) {
        'Suggest' => Icons.lightbulb_rounded,
        'Assist me' || 'Assist' => Icons.auto_awesome_rounded,
        'Autopilot' => Icons.smart_toy_rounded,
        _ => Icons.auto_awesome_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final amount = audioEnergy.clamp(0.0, 1.0).toDouble();
    final turns = (mode == 'Autopilot' ? 0.018 : 0.008) * amount;
    return Transform.rotate(
      angle: turns,
      child: Icon(_icon, size: size),
    );
  }
}
