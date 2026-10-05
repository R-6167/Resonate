import '../core/dj_types.dart';

class DjTransitionBrain {
  const DjTransitionBrain();

  DjTransitionCandidate choose({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
  }) {
    final candidates = generate(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: outgoingPositionMs,
      preferredDurationMs: preferredDurationMs,
      maxDurationMs: maxDurationMs,
    );
    if (candidates.isEmpty) return _fallback(incoming, preferredDurationMs);
    final sorted = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
    return sorted.first;
  }

  List<DjTransitionCandidate> generate({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
  }) {
    final result = <DjTransitionCandidate>[];
    final outRemaining = (outgoing.durationMs ?? 0) - outgoingPositionMs;
    final baseDuration = preferredDurationMs.clamp(2000, maxDurationMs).toInt();

    void add(DjTransitionKind kind, int inMs, int duration, Map<String, double> scores) {
      final risk = _risks(outgoing, incoming, outgoingPositionMs, inMs);
      final confidence = _confidence(outgoing, incoming, scores);
      final score = _weightedScore(scores) - _riskPenalty(risk);
      result.add(DjTransitionCandidate(
        kind: kind,
        outgoingStartMs: outgoingPositionMs,
        incomingStartMs: inMs,
        durationMs: duration.clamp(2000, maxDurationMs).toInt(),
        score: score.clamp(0.0, 1.0).toDouble(),
        confidence: confidence,
        scores: scores,
        risks: risk,
      ));
    }

    final intro = incoming.transitions.bestIntroMs ?? 0;
    final out = outgoing.transitions.bestOutroMs;
    if (out != null && outRemaining > 2500) {
      add(
        DjTransitionKind.outroIntro,
        intro,
        baseDuration,
        _scorePair(outgoing, incoming, outgoingPositionMs, intro, 0.92, 0.90),
      );
    }

    if (outgoing.beatGrid.usable && incoming.beatGrid.usable) {
      final aligned = _nextBeat(incoming, intro);
      add(
        DjTransitionKind.beatBlend,
        aligned,
        baseDuration,
        _scorePair(outgoing, incoming, outgoingPositionMs, aligned, 0.80, 0.78),
      );

      final phrase = _nextPhrase(incoming, aligned);
      add(
        DjTransitionKind.phraseBlend,
        phrase,
        (baseDuration * 1.15).round().clamp(3000, maxDurationMs).toInt(),
        _scorePair(outgoing, incoming, outgoingPositionMs, phrase, 0.92, 0.88),
      );
    }

    final breakdown = _findSection(incoming, DjSectionType.breakdown);
    final drop = _findSection(incoming, DjSectionType.drop);
    if (breakdown != null && drop != null && drop.startMs > breakdown.startMs) {
      add(
        DjTransitionKind.breakdownDrop,
        breakdown.startMs,
        (drop.startMs - breakdown.startMs).clamp(3000, maxDurationMs).toInt(),
        _scorePair(outgoing, incoming, outgoingPositionMs, breakdown.startMs, 0.88, 0.95),
      );
    }

    add(
      DjTransitionKind.energyBridge,
      intro,
      baseDuration,
      _scorePair(outgoing, incoming, outgoingPositionMs, intro, 0.72, 0.72),
    );

    add(
      DjTransitionKind.safeCrossfade,
      intro,
      baseDuration,
      _scorePair(outgoing, incoming, outgoingPositionMs, intro, 0.55, 0.60),
    );

    return result;
  }

  Map<String, double> _scorePair(
    DjTrackProfile a, DjTrackProfile b, int outPos, int inPos,
    double phraseWeight, double structureWeight,
  ) {
    final tempo = _tempoScore(a, b);
    final harmonic = _harmonicScore(a, b);
    final energy = 1 - (a.energyAt(outPos) - b.energyAt(inPos)).abs();
    final spectrum = _spectrumScore(a, b);
    final phrase = _phraseScore(a, b);
    final structure = _structureScore(a, b, outPos, inPos);
    return {
      'tempo': tempo,
      'harmonic': harmonic,
      'energy': energy.clamp(0.0, 1.0).toDouble(),
      'spectrum': spectrum,
      'phrase': (phrase * phraseWeight).clamp(0.0, 1.0).toDouble(),
      'structure': (structure * structureWeight).clamp(0.0, 1.0).toDouble(),
      'confidence': _analysisConfidence(a, b),
    };
  }

  double _weightedScore(Map<String, double> s) {
    final value = (s['tempo'] ?? 0.5) * 0.18 +
        (s['harmonic'] ?? 0.5) * 0.18 +
        (s['energy'] ?? 0.5) * 0.16 +
        (s['spectrum'] ?? 0.5) * 0.10 +
        (s['phrase'] ?? 0.5) * 0.16 +
        (s['structure'] ?? 0.5) * 0.14 +
        (s['confidence'] ?? 0.5) * 0.08;
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _tempoScore(DjTrackProfile a, DjTrackProfile b) {
    final x = a.beatGrid.bpm, y = b.beatGrid.bpm;
    if (x == null || y == null) return 0.5;
    final direct = (x - y).abs() / x;
    final halfDouble = ((x * 2) - y).abs() / (x * 2);
    final d = direct < halfDouble ? direct : halfDouble;
    return (1 - d / 0.20).clamp(0.0, 1.0).toDouble();
  }

  double _harmonicScore(DjTrackProfile a, DjTrackProfile b) {
    if (!a.hasKey || !b.hasKey) return 0.5;
    final rootDistance = (a.keyRoot! - b.keyRoot!).abs();
    final chromatic = rootDistance > 6 ? 12 - rootDistance : rootDistance;
    final mode = a.keyMode == b.keyMode;
    if (chromatic == 0 && mode) return 1.0;
    if (chromatic == 0) return 0.88;
    if (chromatic == 1 && mode) return 0.78;
    if (chromatic == 2 && mode) return 0.58;
    return (0.46 - chromatic * 0.035).clamp(0.12, 0.5).toDouble();
  }

  double _spectrumScore(DjTrackProfile a, DjTrackProfile b) {
    final x = a.spectrum, y = b.spectrum;
    final bass = 1 - (x.bassDensity - y.bassDensity).abs();
    final centroid = 1 - (x.centroid - y.centroid).abs();
    final flux = 1 - (x.spectralFlux - y.spectralFlux).abs();
    return (bass * 0.45 + centroid * 0.30 + flux * 0.25).clamp(0.0, 1.0).toDouble();
  }

  double _phraseScore(DjTrackProfile a, DjTrackProfile b) {
    if (!a.beatGrid.usable || !b.beatGrid.usable) return 0.5;
    return a.beatGrid.beatsPerPhrase == b.beatGrid.beatsPerPhrase ? 1.0 : 0.65;
  }

  double _structureScore(DjTrackProfile a, DjTrackProfile b, int outPos, int inPos) {
    final ao = a.sectionAt(outPos)?.type ?? DjSectionType.unknown;
    final bi = b.sectionAt(inPos)?.type ?? DjSectionType.unknown;
    if (ao == DjSectionType.outro || ao == DjSectionType.breakdown) return 1.0;
    if (bi == DjSectionType.intro || bi == DjSectionType.breakdown) return 1.0;
    if (ao == DjSectionType.chorus && bi == DjSectionType.chorus) return 0.45;
    if (ao == DjSectionType.drop && bi == DjSectionType.drop) return 0.35;
    return 0.65;
  }

  double _analysisConfidence(DjTrackProfile a, DjTrackProfile b) =>
      (a.analysisConfidence * 0.5 + b.analysisConfidence * 0.5).clamp(0.0, 1.0).toDouble();

  double _confidence(DjTrackProfile a, DjTrackProfile b, Map<String, double> s) {
    final known = s.values.where((v) => v > 0).length;
    return ((known / s.length) * _analysisConfidence(a, b)).clamp(0.0, 1.0).toDouble();
  }

  List<DjRiskType> _risks(DjTrackProfile a, DjTrackProfile b, int outPos, int inPos) {
    final risks = <DjRiskType>[];
    if ((a.spectrum.bassDensity - b.spectrum.bassDensity).abs() > 0.45) risks.add(DjRiskType.bassCollision);
    if ((a.energyAt(outPos) - b.energyAt(inPos)).abs() > 0.45) risks.add(DjRiskType.energyShock);
    if (_harmonicScore(a, b) < 0.3) risks.add(DjRiskType.harmonicConflict);
    if (a.sectionAt(outPos)?.type == DjSectionType.drop && b.sectionAt(inPos)?.type == DjSectionType.drop) {
      risks.add(DjRiskType.structureCollision);
    }
    if (!a.beatGrid.usable || !b.beatGrid.usable) risks.add(DjRiskType.lowConfidence);
    return risks;
  }

  double _riskPenalty(List<DjRiskType> risks) {
    var penalty = 0.0;
    for (final risk in risks) {
      penalty += switch (risk) {
        DjRiskType.bassCollision => 0.12,
        DjRiskType.energyShock => 0.12,
        DjRiskType.harmonicConflict => 0.16,
        DjRiskType.structureCollision => 0.15,
        DjRiskType.tempoInstability => 0.10,
        DjRiskType.lowConfidence => 0.04,
      };
    }
    return penalty.clamp(0.0, 0.55).toDouble();
  }

  int _nextBeat(DjTrackProfile profile, int ms) {
    for (final beat in profile.beatGrid.beatMs) {
      if (beat >= ms) return beat;
    }
    final bpm = profile.beatGrid.bpm;
    if (bpm == null) return ms;
    final beatMs = 60000 / bpm;
    final first = profile.beatGrid.firstBeatMs ?? 0;
    final n = ((ms - first) / beatMs).ceil();
    return first + (n * beatMs).round();
  }

  int _nextPhrase(DjTrackProfile profile, int ms) {
    final beats = profile.beatGrid.beatMs;
    final phraseSize = profile.beatGrid.beatsPerPhrase;
    if (beats.length >= phraseSize) {
      final start = beats.indexWhere((b) => b >= ms);
      if (start >= 0) {
        final boundary = start + ((phraseSize - (start % phraseSize)) % phraseSize);
        if (boundary < beats.length) return beats[boundary];
      }
    }
    final beat = _nextBeat(profile, ms);
    final bpm = profile.beatGrid.bpm;
    if (bpm == null) return beat;
    final beatMs = 60000 / bpm;
    final first = profile.beatGrid.firstBeatMs ?? 0;
    final phraseMs = beatMs * profile.beatGrid.beatsPerPhrase;
    final n = ((beat - first) / phraseMs).ceil();
    return first + (n * phraseMs).round();
  }

  DjSection? _findSection(DjTrackProfile profile, DjSectionType type) {
    for (final section in profile.sections) {
      if (section.type == type) return section;
    }
    return null;
  }

  DjTransitionCandidate _fallback(DjTrackProfile b, int duration) {
    return DjTransitionCandidate(
      kind: DjTransitionKind.safeCrossfade,
      outgoingStartMs: 0,
      incomingStartMs: b.transitions.bestIntroMs ?? 0,
      durationMs: duration.clamp(2000, 16000).toInt(),
      score: 0.5,
      confidence: 0.5,
    );
  }
}
