import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/crossfade_frame_volumes.dart';

void main() {
  group('CrossfadeFrameVolumes', () {
    test('preserves outgoing base level and applies master scaling', () {
      final frame = CrossfadeFrameVolumes.calculate(
        base: 0.4,
        master: 0.8,
        frameMaster: 0.4,
        outgoingGain: 0.5,
        incomingGain: 0.5,
      );
      expect(frame.outgoing, closeTo(0.1, 1e-9));
      expect(frame.incoming, closeTo(0.2, 1e-9));
    });

    test('does not boost outgoing audio above captured base', () {
      final frame = CrossfadeFrameVolumes.calculate(
        base: 0.25,
        master: 0.7,
        frameMaster: 0.7,
        outgoingGain: 1.0,
        incomingGain: 0.0,
      );
      expect(frame.outgoing, closeTo(0.25, 1e-9));
      expect(frame.incoming, closeTo(0.0, 1e-9));
    });

    test('clamps output volumes to the valid range', () {
      final frame = CrossfadeFrameVolumes.calculate(
        base: 1.0,
        master: 0.2,
        frameMaster: 1.0,
        outgoingGain: 2.0,
        incomingGain: 2.0,
      );
      expect(frame.outgoing, inInclusiveRange(0.0, 1.0));
      expect(frame.incoming, inInclusiveRange(0.0, 1.0));
      expect(frame.outgoing, lessThanOrEqualTo(1.0));
      expect(frame.incoming, lessThanOrEqualTo(1.0));
    });

    test('intentional master duck scales both engines without boosting', () {
      final frame = CrossfadeFrameVolumes.calculate(
        base: 0.6,
        master: 0.6,
        frameMaster: 0.15,
        outgoingGain: 1.0,
        incomingGain: 1.0,
      );
      expect(frame.outgoing, closeTo(0.15, 1e-9));
      expect(frame.incoming, closeTo(0.15, 1e-9));
    });
  });
}
