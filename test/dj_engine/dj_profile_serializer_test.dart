import 'package:flutter_test/flutter_test.dart';

import 'package:resonate/dj_engine/analysis/dj_profile_serializer.dart';
import 'package:resonate/dj_engine/core/dj_types.dart';

void main() {
  test('V2 profile round-trips rich transition data', () {
    const original = DjTrackProfile(
      songId: 'round-trip',
      durationMs: 180000,
      fingerprint: 'fingerprint',
      beatGrid: DjBeatGrid(
        bpm: 124,
        confidence: 0.82,
        firstBeatMs: 320,
        beatMs: [320, 804, 1288],
        beatsPerBar: 4,
        beatsPerPhrase: 16,
      ),
      keyRoot: 7,
      keyMode: 'minor',
      keyConfidence: 0.74,
      harmonicChanges: [
        DjTimePoint(90000, confidence: 0.6),
      ],
      sections: [
        DjSection(
          type: DjSectionType.breakdown,
          startMs: 60000,
          endMs: 75000,
          confidence: 0.7,
          energy: 0.3,
        ),
      ],
      energyCurve: [
        DjEnergyPoint(
          timeMs: 60000,
          value: 0.4,
          loudness: 0.5,
          bass: 0.3,
          mids: 0.5,
          highs: 0.6,
        ),
      ],
      spectrum: DjSpectralProfile(
        bass: 0.7,
        mids: 0.6,
        highs: 0.5,
        centroid: 0.42,
        bassDensity: 0.65,
        spectralFlux: 0.22,
        confidence: 0.5,
      ),
      transitions: DjTransitionMarkers(
        bestIntroMs: 12000,
        bestOutroMs: 166000,
        safeMixIns: [DjTimePoint(12000, confidence: 0.8)],
        safeMixOuts: [DjTimePoint(166000, confidence: 0.8)],
        riskyPoints: [DjTimePoint(60000, confidence: 0.7)],
      ),
      analysisConfidence: 0.71,
      analysisVersion: 6,
    );

    final serializer = const DjProfileSerializer();
    final decoded = serializer.decode(serializer.encode(original));

    expect(decoded.songId, original.songId);
    expect(decoded.durationMs, original.durationMs);
    expect(decoded.beatGrid.bpm, original.beatGrid.bpm);
    expect(decoded.beatGrid.beatMs, original.beatGrid.beatMs);
    expect(decoded.keyRoot, original.keyRoot);
    expect(decoded.keyMode, original.keyMode);
    expect(decoded.sections.single.type, DjSectionType.breakdown);
    expect(decoded.energyCurve.single.bass, 0.3);
    expect(decoded.spectrum.bassDensity, 0.65);
    expect(decoded.transitions.bestOutroMs, 166000);
    expect(decoded.transitions.riskyPoints.single.timeMs, 60000);
  });
}
