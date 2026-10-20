import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/transport_command_policy.dart';

void main() {
  group('TransportCommandPolicy', () {
    test('preserves transport-priority command classification', () {
      for (final command in [
        'toggle', 'pause', 'stop', 'seek', 'play', 'next', 'previous',
      ]) {
        expect(TransportCommandPolicy.hasTransportPriority(command), isTrue);
      }
      for (final command in ['crossfade', 'preload', 'scan', 'unknown']) {
        expect(TransportCommandPolicy.hasTransportPriority(command), isFalse);
      }
    });

    test('only play, next, and previous supersede queued source mutations', () {
      for (final command in ['play', 'next', 'previous']) {
        expect(TransportCommandPolicy.supersedesPendingSource(command), isTrue);
      }
      for (final command in [
        'toggle', 'pause', 'stop', 'seek', 'crossfade', 'preload',
      ]) {
        expect(TransportCommandPolicy.supersedesPendingSource(command), isFalse);
      }
    });
  });
}
