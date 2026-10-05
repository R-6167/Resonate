/// Core, player-agnostic data types for Resonate's next-generation DJ brain.
///
/// This layer intentionally contains no Flutter, audio-player, or codec code.
/// Analysis may be incomplete: every field is nullable/optional where useful so
/// the engine can degrade to ordinary playback instead of blocking a track.

enum DjSectionType { unknown, intro, verse, preChorus, chorus, drop, breakdown, bridge, build, outro, instrumental }

enum DjTransitionKind { outroIntro, phraseBlend, breakdownDrop, beatBlend, energyBridge, safeCrossfade }

enum DjRiskType { bassCollision, energyShock, harmonicConflict, structureCollision, tempoInstability, lowConfidence }

class DjTimePoint {
  final int timeMs;
  final double confidence;
  const DjTimePoint(this.timeMs, {this.confidence = 1.0});
}

class DjBeatGrid {
  final double? bpm;
  final double confidence;
  final int? firstBeatMs;
  final List<int> beatMs;
  final int beatsPerBar;
  final int beatsPerPhrase;

  const DjBeatGrid({
    this.bpm,
    this.confidence = 0,
    this.firstBeatMs,
    this.beatMs = const [],
    this.beatsPerBar = 4,
    this.beatsPerPhrase = 16,
  });

  bool get usable => bpm != null && bpm! > 40 && bpm! < 240 && confidence >= 0.35;
}

class DjSection {
  final DjSectionType type;
  final int startMs;
  final int endMs;
  final double confidence;
  final double energy;

  const DjSection({
    required this.type,
    required this.startMs,
    required this.endMs,
    this.confidence = 0,
    this.energy = 0.5,
  });

  int get durationMs => (endMs - startMs).clamp(0, 1 << 30);
}

class DjEnergyPoint {
  final int timeMs;
  final double value;
  final double loudness;
  final double bass;
  final double mids;
  final double highs;

  const DjEnergyPoint({
    required this.timeMs,
    required this.value,
    this.loudness = 0.5,
    this.bass = 0.5,
    this.mids = 0.5,
    this.highs = 0.5,
  });
}

class DjSpectralProfile {
  final double bass;
  final double mids;
  final double highs;
  final double centroid;
  final double bassDensity;
  final double spectralFlux;
  final double confidence;

  const DjSpectralProfile({
    this.bass = 0.5,
    this.mids = 0.5,
    this.highs = 0.5,
    this.centroid = 0.5,
    this.bassDensity = 0.5,
    this.spectralFlux = 0.5,
    this.confidence = 0,
  });
}

class DjTransitionMarkers {
  final int? bestIntroMs;
  final int? bestOutroMs;
  final List<DjTimePoint> safeMixIns;
  final List<DjTimePoint> safeMixOuts;
  final List<DjTimePoint> riskyPoints;

  const DjTransitionMarkers({
    this.bestIntroMs,
    this.bestOutroMs,
    this.safeMixIns = const [],
    this.safeMixOuts = const [],
    this.riskyPoints = const [],
  });
}

/// Richer replacement/future companion to the current DjAnalysis model.
class DjTrackProfile {
  final String songId;
  final int? durationMs;
  final String? fingerprint;
  final DjBeatGrid beatGrid;
  final int? keyRoot;
  final String? keyMode;
  final double keyConfidence;
  final List<DjTimePoint> harmonicChanges;
  final List<DjSection> sections;
  final List<DjEnergyPoint> energyCurve;
  final DjSpectralProfile spectrum;
  final DjTransitionMarkers transitions;
  final double analysisConfidence;
  final int analysisVersion;

  const DjTrackProfile({
    required this.songId,
    this.durationMs,
    this.fingerprint,
    this.beatGrid = const DjBeatGrid(),
    this.keyRoot,
    this.keyMode,
    this.keyConfidence = 0,
    this.harmonicChanges = const [],
    this.sections = const [],
    this.energyCurve = const [],
    this.spectrum = const DjSpectralProfile(),
    this.transitions = const DjTransitionMarkers(),
    this.analysisConfidence = 0,
    this.analysisVersion = 1,
  });

  bool get hasKey => keyRoot != null && keyRoot! >= 0 && keyRoot! < 12 && keyMode != null;
  bool get hasTempo => beatGrid.usable;

  DjSection? sectionAt(int positionMs) {
    for (final section in sections) {
      if (positionMs >= section.startMs && positionMs < section.endMs) return section;
    }
    return null;
  }

  double energyAt(int positionMs) {
    if (energyCurve.isEmpty) return 0.5;
    DjEnergyPoint? nearest;
    var distance = 1 << 60;
    for (final point in energyCurve) {
      final d = (point.timeMs - positionMs).abs();
      if (d < distance) {
        distance = d;
        nearest = point;
      }
    }
    return nearest?.value.clamp(0.0, 1.0).toDouble() ?? 0.5;
  }
}

class DjTransitionCandidate {
  final DjTransitionKind kind;
  final int outgoingStartMs;
  final int incomingStartMs;
  final int durationMs;
  final double score;
  final double confidence;
  final Map<String, double> scores;
  final List<DjRiskType> risks;

  const DjTransitionCandidate({
    required this.kind,
    required this.outgoingStartMs,
    required this.incomingStartMs,
    required this.durationMs,
    required this.score,
    required this.confidence,
    this.scores = const {},
    this.risks = const [],
  });

  bool get usable => confidence >= 0.35 && score >= 0.35;
}

class DjExecutionStep {
  final String action;
  final int atMs;
  final Map<String, dynamic> parameters;

  const DjExecutionStep({
    required this.action,
    required this.atMs,
    this.parameters = const {},
  });
}

class DjExecutionPlan {
  final DjTransitionCandidate candidate;
  final List<DjExecutionStep> steps;
  final bool fallback;
  final String reason;

  const DjExecutionPlan({
    required this.candidate,
    this.steps = const [],
    this.fallback = false,
    this.reason = '',
  });
}
