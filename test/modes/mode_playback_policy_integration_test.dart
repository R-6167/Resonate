import 'package:flutter_test/flutter_test.dart';

import 'package:resonate/modes/integration/mode_playback_port.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/providers/mode_provider.dart';
import 'package:resonate/modes/services/mode_policy_catalog.dart';

class _FakePlaybackPort implements ModePlaybackPort {
  bool? crossfadeAllowed;
  bool? shuffleAllowed;
  bool? preciseResume;
  int calls = 0;

  @override
  void applyModePlaybackPolicy({
    required bool crossfadeAllowed,
    required bool shuffleAllowed,
    required bool preciseResume,
  }) {
    this.crossfadeAllowed = crossfadeAllowed;
    this.shuffleAllowed = shuffleAllowed;
    this.preciseResume = preciseResume;
    calls++;
  }
}

void main() {
  test('ModeProvider publishes the complete playback policy for every mode',
      () async {
    final modes = ModeProvider();
    await modes.ready;

    final playback = _FakePlaybackPort();
    modes.attachPlayback(playback);

    for (final mode in ResonateMode.values) {
      await modes.setMode(mode);
      final expected = ModePolicyCatalog.policyFor(mode);

      expect(playback.crossfadeAllowed, expected.crossfadeAllowed,
          reason: '$mode crossfade policy must reach playback');
      expect(playback.shuffleAllowed, expected.shuffleAllowed,
          reason: '$mode shuffle policy must reach playback');
      expect(playback.preciseResume, expected.preciseResume,
          reason: '$mode resume policy must reach playback');
    }

    expect(playback.calls, greaterThanOrEqualTo(ResonateMode.values.length));
    modes.dispose();
  });

  test('mode changes replace, rather than accumulate, playback policy state',
      () async {
    final modes = ModeProvider();
    await modes.ready;

    final playback = _FakePlaybackPort();
    modes.attachPlayback(playback);

    await modes.setMode(ResonateMode.podcast);
    expect(playback.crossfadeAllowed, isFalse);
    expect(playback.shuffleAllowed, isFalse);
    expect(playback.preciseResume, isTrue);

    await modes.setMode(ResonateMode.normal);
    expect(playback.crossfadeAllowed, isTrue);
    expect(playback.shuffleAllowed, isTrue);
    expect(playback.preciseResume, isFalse);

    await modes.setMode(ResonateMode.audiobook);
    expect(playback.crossfadeAllowed, isFalse);
    expect(playback.shuffleAllowed, isFalse);
    expect(playback.preciseResume, isTrue);

    modes.dispose();
  });

  test('attaching playback immediately publishes the current mode policy',
      () async {
    final modes = ModeProvider();
    await modes.ready;
    await modes.setMode(ResonateMode.driving);

    final playback = _FakePlaybackPort();
    modes.attachPlayback(playback);

    final expected = ModePolicyCatalog.policyFor(ResonateMode.driving);
    expect(playback.calls, 1);
    expect(playback.crossfadeAllowed, expected.crossfadeAllowed);
    expect(playback.shuffleAllowed, expected.shuffleAllowed);
    expect(playback.preciseResume, expected.preciseResume);

    modes.dispose();
  });
}
