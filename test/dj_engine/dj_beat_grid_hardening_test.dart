import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:resonate/dj_engine/dj_engine.dart';

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
    final inClick = relative >= 0 &&
        (relative % period) < 18.0;
    final value = inClick
        ? (math.sin(frame * 2 * math.pi * 880 / sampleRate) * 26000).round()
        : 0;
    data.setInt16(frame * 2, value, Endian.little);
  }
  return data.buffer.asUint8List();
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
          pcm: _clickTrack(sampleRate: 11025, bpm: bpm, seconds: 12),
          sampleRate: 11025,
          channels: 1,
          startMs: 0,
          role: 'start',
        ),
        DjDecodedPcmWindow(
          pcm: _clickTrack(
            sampleRate: 11025,
            bpm: bpm,
            seconds: 12,
            phaseMs: 0,
          ),
          sampleRate: 11025,
          channels: 1,
          startMs: 10000,
          role: 'mid',
        ),
      ],
    );

    expect(profile.beatGrid.beatMs.length, greaterThanOrEqualTo(4));
    final gaps = <int>[];
    for (var i = 1; i < profile.beatGrid.beatMs.length; i++) {
      gaps.add(profile.beatGrid.beatMs[i] - profile.beatGrid.beatMs[i - 1]);
    }
    expect(
      gaps.where((gap) => (gap - 500).abs() <= 30).length,
      greaterThan(gaps.length * 0.8),
    );
    final lastBeatMs = profile.beatGrid.beatMs.last;
    expect(lastBeatMs < profile.durationMs, isTrue);
  });

  test('an incompatible local tempo does not create a mixed beat grid', () {
    final profile = analyzer.analyze(
      songId: 'incompatible',
      durationMs: 30000,
      windows: [
        DjDecodedPcmWindow(
          pcm: _clickTrack(sampleRate: 11025, bpm: 120, seconds: 12),
          sampleRate: 11025,
          channels: 1,
          startMs: 0,
          role: 'start',
        ),
        DjDecodedPcmWindow(
          pcm: _clickTrack(sampleRate: 11025, bpm: 80, seconds: 12),
          sampleRate: 11025,
          channels: 1,
          startMs: 10000,
          role: 'mid',
        ),
      ],
    );

    expect(profile.beatGrid.beatMs.length, greaterThanOrEqualTo(4));
    final gaps = <int>[];
    for (var i = 1; i < profile.beatGrid.beatMs.length; i++) {
      gaps.add(profile.beatGrid.beatMs[i] - profile.beatGrid.beatMs[i - 1]);
    }
    final near500 = gaps.where((gap) => (gap - 500).abs() <= 35).length;
    final near750 = gaps.where((gap) => (gap - 750).abs() <= 45).length;
    expect(math.max(near500, near750), greaterThan(gaps.length * 0.7));
  });

  test('beat grid is empty when decoded PCM is too weak to establish a phase', () {
    final profile = analyzer.analyze(
      songId: 'weak',
      durationMs: 20000,
      windows: [
        DjDecodedPcmWindow(
          pcm: Uint8List(11025 * 2),
          sampleRate: 11025,
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
