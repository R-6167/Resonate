import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/dj_engine/dj_engine.dart';

void main() {
  const engine = DjEngine();

  DjTrackProfile track({
    required String id,
    double bpm = 128,
    int key = 0,
    double energy = 0.7,
    DjSectionType section = DjSectionType.outro,
  }) {
    return DjTrackProfile(
      songId: id,
      durationMs: 240000,
      beatGrid: DjBeatGrid(
        bpm: bpm,
        confidence: 0.95,
        firstBeatMs: 0,
        beatMs: const [0, 469, 938, 1406, 1875, 2344, 2813, 3281],
      ),
      keyRoot: key,
      keyMode: 'minor',
      keyConfidence: 0.9,
      sections: [
        DjSection(type: section, startMs: 220000, endMs: 240000, confidence: 0.9, energy: energy),
      ],
      energyCurve: [
        DjEnergyPoint(timeMs: 220000, value: energy),
      ],
      spectrum: const DjSpectralProfile(bassDensity: 0.65, centroid: 0.5, spectralFlux: 0.5, confidence: 0.9),
      transitions: const DjTransitionMarkers(bestIntroMs: 0, bestOutroMs: 220000),
      analysisConfidence: 0.9,
    );
  }

  test('chooses a musical candidate instead of only safe crossfade', () {
    final plan = engine.planTransition(
      outgoing: track(id: 'a', energy: 0.65),
      incoming: track(id: 'b', energy: 0.66, section: DjSectionType.intro),
      outgoingPositionMs: 220000,
    );

    expect(plan.candidate.kind, isNot(DjTransitionKind.safeCrossfade));
    expect(plan.steps, isNotEmpty);
    expect(plan.fallback, isFalse);
  });

  test('keeps a usable fallback when analysis is absent', () {
    const unknown = DjTrackProfile(songId: 'unknown');
    final plan = engine.planTransition(
      outgoing: unknown,
      incoming: unknown,
      outgoingPositionMs: 0,
    );

    expect(plan.candidate.kind, DjTransitionKind.safeCrossfade);
    expect(plan.steps, isNotEmpty);
  });
  test('prefers beat-aligned incoming anchors', () {
    final incoming = track(id: 'b', section: DjSectionType.intro);
    final plan = engine.planTransition(
      outgoing: track(id: 'a'),
      incoming: incoming,
      outgoingPositionMs: 220000,
    );
    expect(const <int>[0, 469, 938, 1406, 1875, 2344, 2813, 3281].contains(plan.candidate.incomingStartMs), isTrue);
  });

  test('uses energy slope when ranking candidates', () {
    final outgoing = track(id: 'a', energy: 0.7);
    final incoming = DjTrackProfile(
      songId: 'b',
      durationMs: 240000,
      beatGrid: const DjBeatGrid(
        bpm: 128,
        confidence: 0.95,
        firstBeatMs: 0,
        beatMs: [0, 469, 938, 1406, 1875, 2344, 2813, 3281],
        downbeatMs: [0, 1875],
        downbeatConfidence: 0.85,
        barConfidence: 0.85,
        phraseConfidence: 0.8,
      ),
      keyRoot: 0,
      keyMode: 'minor',
      keyConfidence: 0.9,
      sections: const [DjSection(type: DjSectionType.intro, startMs: 0, endMs: 20000, confidence: 0.9)],
      energyCurve: const [
        DjEnergyPoint(timeMs: 0, value: 0.5, slope: 0.5),
        DjEnergyPoint(timeMs: 10000, value: 0.7, slope: 0.5),
      ],
      spectrum: const DjSpectralProfile(bassDensity: 0.65, centroid: 0.5, spectralFlux: 0.5, confidence: 0.9),
      transitions: const DjTransitionMarkers(bestIntroMs: 0, bestOutroMs: 220000),
      analysisConfidence: 0.9,
    );
    final plan = engine.planTransition(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: 220000,
    );
    expect(plan.candidate.score, greaterThan(0.0));
  });

}
