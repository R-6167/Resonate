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
}
