import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate/playback/audio_focus_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('pause/resume fade defaults on and persists independently', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AudioFocusSettings();

    await settings.load(prefs);
    expect(settings.pauseResumeFadeEnabled, isTrue);

    settings.pauseResumeFadeEnabled = false;
    await settings.persist();

    final restored = AudioFocusSettings();
    await restored.load(await SharedPreferences.getInstance());
    expect(restored.pauseResumeFadeEnabled, isFalse);
    // The fade preference must not silently change focus automation policy.
    expect(restored.automationEnabled, isTrue);
    expect(restored.clampedLevel, AudioFocusSettings.defaultLevel);
  });
}
