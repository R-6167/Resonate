/// Pure per-frame volume policy for an active A/B crossfade.
///
/// Keeps the existing master-volume scaling and clamps intact. This class
/// deliberately does not write to players or decide transition ownership.
class CrossfadeFrameVolumes {
  const CrossfadeFrameVolumes({required this.outgoing, required this.incoming});

  final double outgoing;
  final double incoming;

  static CrossfadeFrameVolumes calculate({
    required double base,
    required double master,
    required double frameMaster,
    required double outgoingGain,
    required double incomingGain,
  }) {
    final gainScale = (frameMaster / master).clamp(0.0, 1.0);
    return CrossfadeFrameVolumes(
      outgoing: (base * outgoingGain * gainScale).clamp(0.0, 1.0),
      incoming: (frameMaster * incomingGain).clamp(0.0, 1.0),
    );
  }
}
