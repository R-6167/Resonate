/// Advanced, engine-agnostic DJ profile.
///
/// This model deliberately contains more musical context than DjAnalysis.
/// It is safe to persist and can be populated incrementally by offline
/// analyzers. No Flutter/audio-player dependency belongs here.
class DjTrackProfile {
  final String songId;
  final int durationMs;
  final int analysisVersion;

  final TempoProfile tempo;
  final BeatGridProfile beatGrid;
  final HarmonicProfile harmony;
  final StructureProfile structure;
  final EnergyProfile energy;
  final SpectralProfile spectral;
  final TransitionMarkers transition;

  const DjTrackProfile({
    required this.songId,
    required this.durationMs,
    required this.analysisVersion,
    required this.tempo,
    required this.beatGrid,
    required this.harmony,
    required this.structure,
    required this.energy,
    required this.spectral,
    required this.transition,
  });

  bool get usableForDj =>
      durationMs > 0 &&
      tempo.confidence >= 0.35 &&
      beatGrid.confidence >= 0.25;
}

class TempoProfile {
  final double bpm;
  final double confidence;
  final double stability;
  final double? halfBpm;
  final double? doubleBpm;

  const TempoProfile({
    required this.bpm,
    required this.confidence,
    required this.stability,
    this.halfBpm,
    this.doubleBpm,
  });
}

class BeatGridProfile {
  final int offsetMs;
  final double confidence;
  final List<int> beatPositionsMs;
  final List<int> downbeatsMs;
  final int beatsPerBar;
  final int phraseBeats;

  const BeatGridProfile({
    required this.offsetMs,
    required this.confidence,
    required this.beatPositionsMs,
    required this.downbeatsMs,
    this.beatsPerBar = 4,
    this.phraseBeats = 16,
  });
}

class HarmonicProfile {
  final int? root;
  final String? mode;
  final double confidence;
  final List<HarmonicChange> changes;

  const HarmonicProfile({
    this.root,
    this.mode,
    required this.confidence,
    this.changes = const [],
  });
}

class HarmonicChange {
  final int positionMs;
  final int? root;
  final String? mode;
  final double confidence;

  const HarmonicChange({
    required this.positionMs,
    this.root,
    this.mode,
    required this.confidence,
  });
}

class StructureProfile {
  final List<DjSection> sections;
  final double confidence;

  const StructureProfile({
    required this.sections,
    required this.confidence,
  });

  DjSection? get intro => _first(DjSectionType.intro);
  DjSection? get outro => _last(DjSectionType.outro);
  DjSection? get breakdown => _first(DjSectionType.breakdown);
  DjSection? get drop => _first(DjSectionType.drop);

  DjSection? _first(DjSectionType type) {
    for (final section in sections) {
      if (section.type == type) return section;
    }
    return null;
  }

  DjSection? _last(DjSectionType type) {
    for (final section in sections.reversed) {
      if (section.type == type) return section;
    }
    return null;
  }
}

enum DjSectionType {
  unknown,
  intro,
  verse,
  preChorus,
  chorus,
  build,
  drop,
  breakdown,
  bridge,
  outro,
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
    required this.confidence,
    required this.energy,
  });

  int get durationMs => endMs - startMs;
}

class EnergyProfile {
  final double integrated;
  final double confidence;
  final List<EnergyPoint> curve;

  const EnergyProfile({
    required this.integrated,
    required this.confidence,
    this.curve = const [],
  });
}

class EnergyPoint {
  final int positionMs;
  final double value;

  const EnergyPoint({required this.positionMs, required this.value});
}

class SpectralProfile {
  final double bassRatio;
  final double midRatio;
  final double highRatio;
  final double centroid;
  final double confidence;

  const SpectralProfile({
    required this.bassRatio,
    required this.midRatio,
    required this.highRatio,
    required this.centroid,
    required this.confidence,
  });
}

class TransitionMarkers {
  final List<MixWindow> outgoingWindows;
  final List<MixWindow> incomingWindows;
  final List<MixWindow> riskyWindows;

  const TransitionMarkers({
    this.outgoingWindows = const [],
    this.incomingWindows = const [],
    this.riskyWindows = const [],
  });
}

class MixWindow {
  final int startMs;
  final int endMs;
  final double quality;
  final String reason;

  const MixWindow({
    required this.startMs,
    required this.endMs,
    required this.quality,
    required this.reason,
  });
}
