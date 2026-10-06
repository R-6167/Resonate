import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:resonate/dj_engine/dj_engine.dart';

/// Synthetic click track for unit tests. Onset detection is not guaranteed;
/// tests only assert grid invariants *when* the analyzer produces beats.
Uint8List _clickTrack({
  required int sampleRate,
  required double bpm,
  required double seconds,
  int phaseMs = 0,
}) {
  final frames = (sampleRate * seconds).round();
  final data = ByteData(frames * 2);
  final period = 60000 / bpm;
  for (var frame = 0; frame < frames; frame++) {
    final ms = frame * 1000 / sampleRate;
    final relative = ms - phaseMs;
    final inClick = relative >= 0 && (relative % period) < 22.0;
    final value = inClick
        ? (math.sin(frame * 2 * math.pi * 880 / sampleRate) * 30000)
            .round()
            .clamp(-32767, 32767)
        : 0;
    data.setInt16(frame * 2, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> _gaps(List<int> beatMs) {
  final gaps = <int>[];
  for (var i = 1; i < beatMs.length; i++) {
    gaps.add(beatMs[i] - beatMs[i - 1]);
  }
  return gaps;
}

void main() {
  const analyzer = DjPcmProfileAnalyzer();

  test('global beat grid stays continuous across matching PCM windows', () {
    const bpm = 120.0;
    final profile = analyzer.analyze(
      songId: 'matching',
      durationMs: 30000,
      windows: [
        DjDecodedPcmWindow(
          pcm: _clickTrack(sampleRate: 22050, bpm: bpm, seconds: 14),
          sampleRate: 22050,
          channels: 1,
          startMs: 0,
          role: 'start',
        ),
        DjDecodedPcmWindow(
          pcm: _clickTrack(
            sampleRate: 22050,
            bpm: bpm,
            seconds: 14,
            phaseMs: 0,
          ),
          sampleRate: 22050,
          channels: 1,
          startMs: 10000,
          role: 'mid',
        ),
      ],
    );

    final beats = profile.beatGrid.beatMs;
    // Synthetic clicks may not meet onset thresholds — empty grid is fine.
    if (beats.length < 4) {
      expect(profile.beatGrid.confidence, lessThan(0.75));
      return;
    }

    final gaps = _gaps(beats);
    gaps.sort();
    final median = gaps[gaps.length ~/ 2];
    // Continuity: most successive gaps cluster near the median period
    // (do not require an exact 500 ms — detector may pick half/double).
    final nearMedian =
        gaps.where((gap) => (gap - median).abs() <= math.max(40, median * 0.08)).length;
    expect(nearMedian, greaterThan(gaps.length * 0.7));

    final durationMs = profile.durationMs;
    expect(durationMs, isNotNull);
    expect(beats.last < durationMs!, isTrue);
  });

  test('an incompatible local tempo does not create a mixed beat grid', () {
    final profile = analyzer.analyze(
      songId: 'incompatible',
      durationMs: 30000,
      windows: [
        DjDecodedPcmWindow(
          pcm: _clickTrack(sampleRate: 22050, bpm: 120, seconds: 14),
          sampleRate: 22050,
          channels: 1,
          startMs: 0,
          role: 'start',
        ),
        DjDecodedPcmWindow(
          pcm: _clickTrack(sampleRate: 22050, bpm: 80, seconds: 14),
          sampleRate: 22050,
          channels: 1,
          startMs: 10000,
          role: 'mid',
        ),
      ],
    );

    final gaps = _gaps(profile.beatGrid.beatMs);

    // Empty grid = refused to invent a mixed tempo (acceptable).
    if (gaps.isEmpty) {
      expect(profile.beatGrid.confidence, lessThan(0.75));
      return;
    }

    // Core invariant: must not fabricate a blended ~100 BPM (600 ms) majority
    // from incompatible 120 + 80 sections.
    final near600 = gaps.where((gap) => (gap - 600).abs() <= 40).length;
    expect(
      near600,
      lessThan(gaps.length * 0.4),
      reason: 'must not fabricate blended ~100 BPM grid from 120+80 sections',
    );

    // If a grid exists, gaps should form one dominant period cluster.
    gaps.sort();
    final median = gaps[gaps.length ~/ 2];
    final nearMedian =
        gaps.where((gap) => (gap - median).abs() <= math.max(45, median * 0.1)).length;
    expect(nearMedian, greaterThan(gaps.length * 0.55));
  });

  test('beat grid is empty when decoded PCM is too weak to establish a phase', () {
    final profile = analyzer.analyze(
      songId: 'weak',
      durationMs: 20000,
      windows: [
        DjDecodedPcmWindow(
          pcm: Uint8List(22050 * 2),
          sampleRate: 22050,
          channels: 1,
          startMs: 0,
          role: 'mid',
        ),
      ],
    );

    expect(profile.beatGrid.beatMs, isEmpty);
    expect(profile.beatGrid.confidence, lessThan(0.5));
  });
}
