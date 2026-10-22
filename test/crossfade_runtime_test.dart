import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/crossfade_runtime.dart';

void main() {
  group('CrossfadeRuntime ownership contract', () {
    test('automatic generations only advance when explicitly invalidated', () {
      final runtime = CrossfadeRuntime();

      expect(runtime.automaticTransitionGeneration, 0);
      expect(runtime.bumpAutomaticGeneration(), 1);
      expect(runtime.ownsAutomaticGeneration(1), isTrue);

      expect(runtime.bumpAutomaticGeneration(), 2);
      expect(runtime.ownsAutomaticGeneration(1), isFalse);
      expect(runtime.ownsAutomaticGeneration(2), isTrue);
    });

    test('clearing flags does not revive an older automatic transition', () {
      final runtime = CrossfadeRuntime();
      final oldGeneration = runtime.bumpAutomaticGeneration();
      runtime.inProgress = true;
      runtime.automaticInFlight = true;
      runtime.preloadInFlight = true;
      runtime.preloadedNextSongId = 'next';
      runtime.repeatSelfHandoffArmed = true;
      runtime.repeatSelfHandoffInFlight = true;
      runtime.repeatSelfTargetSongId = 'current';

      runtime.clearFlags();

      expect(runtime.ownsAutomaticGeneration(oldGeneration), isTrue);
      expect(runtime.isLive, isFalse);
      expect(runtime.hasPreload, isFalse);
      expect(runtime.hasRepeatSelfHandoff, isFalse);
      expect(runtime.hasAutomaticWork, isFalse);
      expect(runtime.preloadedNextSongId, isNull);
      expect(runtime.repeatSelfTargetSongId, isNull);
    });

    test('reports every automatic-work category until each is cleared', () {
      final runtime = CrossfadeRuntime();

      runtime.inProgress = true;
      expect(runtime.hasAutomaticWork, isTrue);
      runtime.inProgress = false;

      runtime.preloadInFlight = true;
      expect(runtime.hasAutomaticWork, isTrue);
      runtime.preloadInFlight = false;

      runtime.repeatSelfHandoffArmed = true;
      expect(runtime.hasAutomaticWork, isTrue);
      runtime.clearRepeatSelf();

      expect(runtime.hasAutomaticWork, isFalse);
    });

    test('can clear active flags while preserving a repeat-self generation', () {
      final runtime = CrossfadeRuntime();
      final repeatGeneration = runtime.bumpRepeatSelfGeneration();
      runtime.repeatSelfHandoffArmed = true;
      runtime.repeatSelfTargetSongId = 'track-a';
      runtime.inProgress = true;

      runtime.clearFlags(clearRepeatSelf: false);

      expect(runtime.ownsRepeatSelfGeneration(repeatGeneration), isTrue);
      expect(runtime.repeatSelfHandoffArmed, isTrue);
      expect(runtime.repeatSelfTargetSongId, 'track-a');
      expect(runtime.inProgress, isFalse);
    });
  });
}
