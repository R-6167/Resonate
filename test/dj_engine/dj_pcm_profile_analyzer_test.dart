import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:resonate/dj_engine/dj_engine.dart';

void main() {
  test('PCM profile analyzer is codec-agnostic at the decoded PCM boundary', () {
    final analyzer = const DjPcmProfileAnalyzer();
    final profile = analyzer.analyze(
      songId: 'pcm-test',
      durationMs: 120000,
      windows: [
        DjDecodedPcmWindow(
          pcm: Uint8List(44100 * 2),
          sampleRate: 44100,
          channels: 1,
          startMs: 0,
          role: 'start',
        ),
      ],
    );

    expect(profile.songId, 'pcm-test');
    expect(profile.durationMs, 120000);
    expect(profile.hasTempo, isFalse);
    expect(profile.hasKey, isFalse);
  });

  test('empty PCM windows produce a safe profile instead of throwing', () {
    final profile = const DjPcmProfileAnalyzer().analyze(
      songId: 'empty',
      durationMs: 180000,
      windows: const [],
    );

    expect(profile.hasTempo, isFalse);
    expect(profile.hasKey, isFalse);
    expect(profile.analysisConfidence, 0);
  });
}
