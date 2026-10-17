import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/services/playback_coordinator.dart';
import 'package:resonate/services/playback_intent_gate.dart';

void main() {
  test('newer playback intent invalidates stale work', () {
    final gate = PlaybackIntentGate();
    final first = gate.issue();
    expect(gate.isCurrent(first), isTrue);
    final second = gate.issue();
    expect(second, greaterThan(first));
    expect(gate.isCurrent(first), isFalse);
    expect(gate.isCurrent(second), isTrue);
  });

  test('newest queued user source request supersedes stale queued request', () async {
    final coordinator = PlaybackCoordinator();
    final started = Completer<void>();
    final release = Completer<void>();
    var staleRan = false;
    var latestRan = false;

    final active = coordinator.runSourceMutation(() async {
      started.complete();
      await release.future;
      return 'active';
    }, command: 'play');
    await started.future;

    final stale = coordinator.runSourceMutation(() async {
      staleRan = true;
      return 'stale';
    }, command: 'play', supersedePending: true,
       onSuperseded: () async => 'superseded');
    final latest = coordinator.runSourceMutation(() async {
      latestRan = true;
      return 'latest';
    }, command: 'play', supersedePending: true,
       onSuperseded: () async => 'superseded');

    release.complete();
    expect(await active, 'active');
    expect(await stale, 'superseded');
    expect(await latest, 'latest');
    expect(staleRan, isFalse);
    expect(latestRan, isTrue);
  });
}
