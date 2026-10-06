import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate/modes/integration/mode_context_port.dart';
import 'package:resonate/modes/integration/mode_playback_port.dart';
import 'package:resonate/modes/models/mode_action.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/providers/mode_provider.dart';

class FakePlayback implements ModePlaybackPort {
  bool? crossfade;
  bool? shuffle;
  bool? preciseResume;

  @override
  void applyModePlaybackPolicy({
    required bool crossfadeAllowed,
    required bool shuffleAllowed,
    required bool preciseResume,
  }) {
    crossfade = crossfadeAllowed;
    shuffle = shuffleAllowed;
    this.preciseResume = preciseResume;
  }
}

class FakeContext implements ModeContextPort {
  ModeAudioContext _context = ModeAudioContext.unknown;
  final listeners = <void Function()>[];

  @override
  ModeAudioContext get audioContext => _context;

  void setContext(ModeAudioContext value) {
    _context = value;
    for (final listener in List.of(listeners)) {
      listener();
    }
  }

  @override
  void addListener(void Function() listener) => listeners.add(listener);

  @override
  void removeListener(void Function() listener) => listeners.remove(listener);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('mode changes push policy through the playback boundary', () async {
    final playback = FakePlayback();
    final provider = ModeProvider();
    await provider.ready;
    provider.attachPlayback(playback);

    await provider.setMode(ResonateMode.podcast);

    expect(playback.crossfade, isFalse);
    expect(playback.shuffle, isFalse);
    expect(playback.preciseResume, isTrue);
    provider.dispose();
  });

  test('car context offers Driving without touching playback directly', () async {
    final provider = ModeProvider();
    final context = FakeContext();
    await provider.ready;
    provider.attachContext(context);

    context.setContext(ModeAudioContext.car);

    expect(provider.hasDrivingSuggestion, isTrue);
    expect(provider.mode, ResonateMode.normal);
    provider.dispose();
  });

  test('running mode exposes its two-finger interaction contract', () async {
    final provider = ModeProvider();
    await provider.ready;

    await provider.setMode(ResonateMode.running);

    expect(provider.interactionPolicy.minimumTapPointers, 2);
    expect(
      provider.interactionPolicy.requiresTwoFingerTap(ModeAction.playPause),
      isTrue,
    );
    provider.dispose();
  });

  test('auto-enter Driving switches mode when car context appears', () async {
    final provider = ModeProvider();
    final context = FakeContext();
    await provider.ready;
    provider.attachContext(context);
    await provider.setAutoEnterDrivingOnCar(true);

    context.setContext(ModeAudioContext.car);
    await Future<void>.delayed(Duration.zero);

    expect(provider.mode, ResonateMode.driving);
    expect(provider.hasDrivingSuggestion, isFalse);
    provider.dispose();
  });
}
