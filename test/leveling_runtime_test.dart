import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/leveling_runtime.dart';

void main() {
  group('LevelingRuntime', () {
    test('keeps user preamp and track trim separate', () {
      final runtime = LevelingRuntime();
      runtime.setUserPreampScale(0.5);
      runtime.setTrackScale(0.4);
      expect(runtime.userPreampScale, 0.5);
      expect(runtime.trackScale, 0.4);
      expect(runtime.effectivePreampScale, closeTo(0.2, 1e-9));
    });

    test('clamps both scales without allowing track gain above unity', () {
      final runtime = LevelingRuntime();
      runtime.setUserPreampScale(2.0);
      runtime.setTrackScale(3.0);
      expect(runtime.userPreampScale, 1.0);
      expect(runtime.trackScale, 1.0);
      expect(runtime.effectivePreampScale, 1.0);
      runtime.setTrackScale(-1.0);
      expect(runtime.trackScale, 0.0);
      expect(runtime.effectivePreampScale, 0.0);
    });

    test('only the newest refresh generation remains current', () {
      final runtime = LevelingRuntime();
      final first = runtime.beginRefresh();
      final second = runtime.beginRefresh();
      expect(runtime.isCurrentRefresh(first), isFalse);
      expect(runtime.isCurrentRefresh(second), isTrue);
      runtime.refreshGeneration++;
      expect(runtime.isCurrentRefresh(second), isFalse);
    });
  });
}
