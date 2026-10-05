import '../core/dj_types.dart';

class DjRiskEngine {
  const DjRiskEngine();

  List<DjRiskType> evaluate({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required DjTransitionCandidate candidate,
  }) {
    final risks = <DjRiskType>[...candidate.risks];
    if (candidate.durationMs < 2500) risks.add(DjRiskType.structureCollision);

    final outEnergy = outgoing.energyAt(candidate.outgoingStartMs);
    final inEnergy = incoming.energyAt(candidate.incomingStartMs);
    if ((outEnergy - inEnergy).abs() > 0.5) risks.add(DjRiskType.energyShock);

    if ((outgoing.spectrum.bassDensity - incoming.spectrum.bassDensity).abs() > 0.5) {
      risks.add(DjRiskType.bassCollision);
    }
    if (outgoing.hasKey && incoming.hasKey) {
      final rootDistance = (outgoing.keyRoot! - incoming.keyRoot!).abs();
      final chromatic = rootDistance > 6 ? 12 - rootDistance : rootDistance;
      if (chromatic >= 4 && outgoing.keyMode != incoming.keyMode) {
        risks.add(DjRiskType.harmonicConflict);
      }
    }
    final tempoA = outgoing.beatGrid.bpm;
    final tempoB = incoming.beatGrid.bpm;
    if (tempoA != null && tempoB != null) {
      final ratio = tempoA > tempoB ? tempoA / tempoB : tempoB / tempoA;
      if (ratio > 1.20 && ratio < 1.80) risks.add(DjRiskType.tempoInstability);
    }
    if (candidate.confidence < 0.35 ||
        outgoing.beatGrid.confidence < 0.35 ||
        incoming.beatGrid.confidence < 0.35) {
      risks.add(DjRiskType.lowConfidence);
    }
    return risks.toSet().toList();
  }

  double severity(Iterable<DjRiskType> risks) {
    var value = 0.0;
    for (final risk in risks) {
      value += switch (risk) {
        DjRiskType.bassCollision => 0.75,
        DjRiskType.energyShock => 0.65,
        DjRiskType.harmonicConflict => 0.85,
        DjRiskType.structureCollision => 0.70,
        DjRiskType.tempoInstability => 0.60,
        DjRiskType.lowConfidence => 0.25,
      };
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}
