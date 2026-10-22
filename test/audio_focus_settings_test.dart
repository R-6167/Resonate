import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate/playback/audio_focus_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('focus levels clamp and auto-resume requires automation plus level 3+', () {
    final settings = AudioFocusSettings();

    expect(settings.useDeepDuck, isFalse);
    expect(settings.mayAutoResume, isFalse);

    settings.setLevel(1);
    expect(settings.clampedLevel, 1);
    expect(settings.useDeepDuck, isTrue);
    expect(settings.mayAutoResume, isFalse);

    settings.setLevel(3);
    expect(settings.mayAutoResume, isTrue);

    settings.setAutomationEnabled(false);
    expect(settings.mayAutoResume, isFalse);

    settings.setAutomationEnabled(true);
    settings.setLevel(99);
    expect(settings.clampedLevel, AudioFocusSettings.maxLevel);
    expect(settings.mayAutoResume, isTrue);

    settings.setLevel(-99);
    expect(settings.clampedLevel, AudioFocusSettings.minLevel);
  });

  test('load clamps invalid stored level and keeps fade setting independent', () async {
    SharedPreferences.setMockInitialValues({
      AudioFocusSettings.levelKey: 99,
      AudioFocusSettings.automationKey: false,
      AudioFocusSettings.pauseResumeFadeKey: false,
    });
    final settings = AudioFocusSettings();
    await settings.load(await SharedPreferences.getInstance());

    expect(settings.clampedLevel, AudioFocusSettings.maxLevel);
    expect(settings.automationEnabled, isFalse);
    expect(settings.pauseResumeFadeEnabled, isFalse);
    expect(settings.mayAutoResume, isFalse);
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
