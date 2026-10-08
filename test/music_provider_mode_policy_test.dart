import 'package:flutter_test/flutter_test.dart';

import 'package:resonate/providers/music_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MusicProvider enforces Mode playback gates independently of user state', () {
    final music = MusicProvider();

    music.applyModePlaybackPolicy(
      crossfadeAllowed: false,
      shuffleAllowed: false,
      preciseResume: true,
    );

    expect(music.modeCrossfadeAllowed, isFalse);
    expect(music.modeShuffleAllowed, isFalse);
    expect(music.modePreciseResume, isTrue);
    expect(music.effectiveCrossfadeEnabled, isFalse);
    expect(music.effectiveShuffleEnabled, isFalse);
    expect(music.canContinueListening, isFalse);

    music.applyModePlaybackPolicy(
      crossfadeAllowed: true,
      shuffleAllowed: true,
      preciseResume: false,
    );

    expect(music.modeCrossfadeAllowed, isTrue);
    expect(music.modeShuffleAllowed, isTrue);
    expect(music.modePreciseResume, isFalse);
    expect(music.effectiveCrossfadeEnabled, isFalse);
    expect(music.effectiveShuffleEnabled, isFalse);
    expect(music.canContinueListening, isFalse);

    music.dispose();
  });

  test('MusicProvider keeps user crossfade preference subordinate to Mode gate',
      () async {
    final music = MusicProvider();

    await music.setCrossfadeEnabled(true);
    expect(music.crossfadeEnabled, isTrue);
    expect(music.effectiveCrossfadeEnabled, isTrue);

    music.applyModePlaybackPolicy(
      crossfadeAllowed: false,
      shuffleAllowed: true,
      preciseResume: false,
    );

    expect(music.crossfadeEnabled, isTrue,
        reason: 'Mode must not overwrite the user preference');
    expect(music.effectiveCrossfadeEnabled, isFalse,
        reason: 'Mode policy must still gate actual crossfade use');

    music.applyModePlaybackPolicy(
      crossfadeAllowed: true,
      shuffleAllowed: true,
      preciseResume: false,
    );
    expect(music.effectiveCrossfadeEnabled, isTrue);

    music.dispose();
  });
}
