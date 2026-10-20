import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/crossfade_fallback_fade.dart';

void main() {
  group('CrossfadeFallbackFade', () {
    test('starts at full gain and ends silent', () {
      expect(CrossfadeFallbackFade.outgoingGain(0), closeTo(1, 1e-9));
      expect(CrossfadeFallbackFade.outgoingGain(1), closeTo(0, 1e-9));
    });

    test('decreases monotonically throughout the fallback ramp', () {
      var previous = CrossfadeFallbackFade.outgoingGain(0);
      for (var step = 1; step <= 20; step++) {
        final gain = CrossfadeFallbackFade.outgoingGain(step / 20);
        expect(gain, inInclusiveRange(0.0, 1.0));
        expect(gain, lessThanOrEqualTo(previous));
        previous = gain;
      }
    });

    test('clamps progress outside the fade window', () {
      expect(CrossfadeFallbackFade.outgoingGain(-1), closeTo(1, 1e-9));
      expect(CrossfadeFallbackFade.outgoingGain(2), closeTo(0, 1e-9));
    });
  });
}
