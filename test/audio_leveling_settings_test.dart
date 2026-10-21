import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate/playback/audio_leveling_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to disabled with a bounded sampled-RMS target', () async {
    final settings = AudioLevelingSettings();
    await settings.load(await SharedPreferences.getInstance());

    expect(settings.enabled, isFalse);
    expect(settings.targetRmsDbfs, AudioLevelingSettings.defaultTargetRmsDbfs);
    expect(settings.clampedTarget, inInclusiveRange(-24.0, -12.0));
  });

  test('clamps target, rejects non-finite values, and persists independently', () async {
    final settings = AudioLevelingSettings();
    await settings.load(await SharedPreferences.getInstance());

    expect(settings.setTargetRmsDbfs(-40), isTrue);
    expect(settings.targetRmsDbfs, -24);
    expect(settings.setTargetRmsDbfs(double.nan), isFalse);
    expect(settings.setTargetRmsDbfs(double.infinity), isFalse);
    expect(settings.setTargetRmsDbfs(-12), isTrue);
    settings.setEnabled(true);
    await settings.persist();

    final restored = AudioLevelingSettings();
    await restored.load(await SharedPreferences.getInstance());
    expect(restored.enabled, isTrue);
    expect(restored.targetRmsDbfs, -12);
  });

  test('setting an unchanged value does not report a change', () async {
    final settings = AudioLevelingSettings();
    await settings.load(await SharedPreferences.getInstance());

    expect(settings.setEnabled(false), isFalse);
    expect(settings.setTargetRmsDbfs(settings.targetRmsDbfs), isFalse);
  });
}
