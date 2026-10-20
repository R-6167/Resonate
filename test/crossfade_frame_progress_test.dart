import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/crossfade_frame_progress.dart';

void main() {
  group('CrossfadeFrameProgress', () {
    test('starts at zero and reaches one at the planned duration', () {
      expect(
        CrossfadeFrameProgress.calculate(elapsedMs: 0, totalMs: 1000).fraction,
        0.0,
      );
      expect(
        CrossfadeFrameProgress.calculate(elapsedMs: 1000, totalMs: 1000).fraction,
        1.0,
      );
    });

    test('returns normalized progress between the endpoints', () {
      expect(
        CrossfadeFrameProgress.calculate(elapsedMs: 250, totalMs: 1000).fraction,
        0.25,
      );
    });

    test('clamps early and late elapsed values', () {
      expect(
        CrossfadeFrameProgress.calculate(elapsedMs: -10, totalMs: 1000).fraction,
        0.0,
      );
      expect(
        CrossfadeFrameProgress.calculate(elapsedMs: 1200, totalMs: 1000).fraction,
        1.0,
      );
    });

    test('treats a non-positive duration as complete rather than dividing by zero', () {
      expect(
        CrossfadeFrameProgress.calculate(elapsedMs: 0, totalMs: 0).fraction,
        1.0,
      );
      expect(
        CrossfadeFrameProgress.calculate(elapsedMs: 0, totalMs: -1).fraction,
        1.0,
      );
    });
  });
}
