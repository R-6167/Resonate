import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/volume_facade.dart';

void main() {
  group('VolumeFacade', () {
    test('clamps user volume and sleep fade independently', () {
      final facade = VolumeFacade();
      facade.setUserVolume(1.4);
      facade.setSleepFadeScale(-0.5);
      expect(facade.userVolume, 1.0);
      expect(facade.sleepFadeScale, 0.0);
      facade.setUserVolume(0.35);
      facade.setSleepFadeScale(0.6);
      expect(facade.userVolume, 0.35);
      expect(facade.sleepFadeScale, 0.6);
    });

    test('normalizes system volume and ignores invalid or tiny changes', () {
      final facade = VolumeFacade();
      expect(facade.updateSystemVolume(5, 0), isFalse);
      expect(facade.updateSystemVolume(50, 100), isTrue);
      expect(facade.userVolume, 0.5);
      expect(facade.updateSystemVolume(50.05, 100), isFalse);
      expect(facade.updateSystemVolume(150, 100), isTrue);
      expect(facade.userVolume, 1.0);
    });

    test('poll generations identify stale overlapping polls', () {
      final facade = VolumeFacade();
      final first = facade.beginSystemVolumePoll();
      final second = facade.beginSystemVolumePoll();
      expect(facade.isCurrentSystemVolumePoll(first), isFalse);
      expect(facade.isCurrentSystemVolumePoll(second), isTrue);
    });
  });
}
