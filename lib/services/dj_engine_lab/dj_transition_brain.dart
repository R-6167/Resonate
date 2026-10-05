import 'dj_track_profile.dart';

/// Candidate-based transition planner.
///
/// Unlike the legacy planner, this does not immediately pick one strategy.
/// It creates several musically plausible candidates, scores them, and lets
/// the execution layer choose the safest high-quality plan.
class DjTransitionBrain {
  const DjTransitionBrain();

  List<DjTransitionCandidate> generate(
    DjTrackProfile outgoing,
    DjTrackProfile incoming,
  ) {
    final candidates = <DjTransitionCandidate>[
      _outroToIntro(outgoing, incoming),
      _phraseBlend(outgoing, incoming),
      _breakdownToDrop(outgoing, incoming),
      _beatBlend(outgoing, incoming),
    ];

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  DjTransitionCandidate _outroToIntro(
    DjTrackProfile a,
    DjTrackProfile b,
  ) {
    final out = a.transition.outgoingWindows.isEmpty
        ? a.structure.outro
        : a.transition.outgoingWindows.last;
    final input = b.transition.incomingWindows.isEmpty
        ? b.structure.intro
        : b.transition.incomingWindows.first;

    final score = _score(
      bpm: _bpm(a, b),
      harmonic: _harmonic(a, b),
      energy: _energy(a, b),
      structure: out != null && input != null ? 0.95 : 0.55,
      confidence: _confidence(a, b),
    );

    return DjTransitionCandidate(
      type: DjTransitionType.outroToIntro,
      score: score,
      startOutgoingMs: out is DjSection ? out.startMs : (out as MixWindow?)?.startMs,
      incomingStartMs: input is DjSection ? input.startMs : (input as MixWindow?)?.startMs,
      reason: 'Clean structural handoff between outgoing outro and incoming intro.',
    );
  }

  DjTransitionCandidate _phraseBlend(
    DjTrackProfile a,
    DjTrackProfile b,
  ) {
    final score = _score(
      bpm: _bpm(a, b),
      harmonic: _harmonic(a, b),
      energy: _energy(a, b),
      structure: _phraseCompatibility(a, b),
      confidence: _confidence(a, b),
    );
    return DjTransitionCandidate(
      type: DjTransitionType.phraseBlend,
      score: score,
      startOutgoingMs: _lastSafeBeat(a),
      incomingStartMs: _firstSafeBeat(b),
      reason: 'Phrase-aligned blend for continuous musical flow.',
    );
  }

  DjTransitionCandidate _breakdownToDrop(
    DjTrackProfile a,
    DjTrackProfile b,
  ) {
    final hasA = a.structure.breakdown != null;
    final hasB = b.structure.drop != null;
    final score = _score(
      bpm: _bpm(a, b),
      harmonic: _harmonic(a, b),
      energy: hasA && hasB ? 1.0 : _energy(a, b),
      structure: hasA && hasB ? 1.0 : 0.35,
      confidence: _confidence(a, b),
    );
    return DjTransitionCandidate(
      type: DjTransitionType.breakdownToDrop,
      score: score,
      startOutgoingMs: a.structure.breakdown?.startMs,
      incomingStartMs: b.structure.drop?.startMs,
      reason: 'Uses a low-energy breakdown to prepare the incoming drop.',
    );
  }

  DjTransitionCandidate _beatBlend(
    DjTrackProfile a,
    DjTrackProfile b,
  ) {
    final score = _score(
      bpm: _bpm(a, b),
      harmonic: _harmonic(a, b),
      energy: _energy(a, b),
      structure: 0.70,
      confidence: _confidence(a, b),
    );
    return DjTransitionCandidate(
      type: DjTransitionType.beatBlend,
      score: score,
      startOutgoingMs: _lastSafeBeat(a),
      incomingStartMs: _firstSafeBeat(b),
      reason: 'Beat-grid blend fallback with minimal structural assumptions.',
    );
  }

  double _score({
    required double bpm,
    required double harmonic,
    required double energy,
    required double structure,
    required double confidence,
  }) {
    return (0.22 * bpm +
            0.22 * harmonic +
            0.18 * energy +
            0.23 * structure +
            0.15 * confidence)
        .clamp(0.0, 1.0);
  }

  double _bpm(DjTrackProfile a, DjTrackProfile b) {
    final x = a.tempo.bpm;
    final y = b.tempo.bpm;
    if (x <= 0 || y <= 0) return 0.0;
    final direct = (x - y).abs() / x;
    final half = (x - y * 2).abs() / x;
    final doubled = (x * 2 - y).abs() / x;
    return (1.0 - [direct, half, doubled].reduce((p, q) => p < q ? p : q))
        .clamp(0.0, 1.0);
  }

  double _harmonic(DjTrackProfile a, DjTrackProfile b) {
    if (a.harmony.root == null || b.harmony.root == null) return 0.45;
    final distance = (a.harmony.root! - b.harmony.root!).abs();
    final pitchDistance = distance > 6 ? 12 - distance : distance;
    final mode = a.harmony.mode == b.harmony.mode ? 1.0 : 0.78;
    return (1.0 - pitchDistance / 6.0).clamp(0.0, 1.0) * mode;
  }

  double _energy(DjTrackProfile a, DjTrackProfile b) {
    return (1.0 - (a.energy.integrated - b.energy.integrated).abs())
        .clamp(0.0, 1.0);
  }

  double _phraseCompatibility(DjTrackProfile a, DjTrackProfile b) {
    return a.beatGrid.phraseBeats == b.beatGrid.phraseBeats ? 1.0 : 0.72;
  }

  double _confidence(DjTrackProfile a, DjTrackProfile b) {
    return ((a.tempo.confidence +
                a.beatGrid.confidence +
                a.harmony.confidence +
                b.tempo.confidence +
                b.beatGrid.confidence +
                b.harmony.confidence) /
            6.0)
        .clamp(0.0, 1.0);
  }

  int? _lastSafeBeat(DjTrackProfile p) =>
      p.beatGrid.beatPositionsMs.isEmpty ? null : p.beatGrid.beatPositionsMs.last;

  int? _firstSafeBeat(DjTrackProfile p) =>
      p.beatGrid.beatPositionsMs.isEmpty ? null : p.beatGrid.beatPositionsMs.first;
}

enum DjTransitionType {
  outroToIntro,
  phraseBlend,
  breakdownToDrop,
  beatBlend,
}

class DjTransitionCandidate {
  final DjTransitionType type;
  final double score;
  final int? startOutgoingMs;
  final int? incomingStartMs;
  final String reason;

  const DjTransitionCandidate({
    required this.type,
    required this.score,
    required this.startOutgoingMs,
    required this.incomingStartMs,
    required this.reason,
  });
}
