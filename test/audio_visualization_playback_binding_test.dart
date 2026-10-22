import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:resonate/providers/audio_visualization_provider.dart';

class _FakePlayback extends ChangeNotifier {
  bool isPlaying = false;

  void setPlaying(bool value) {
    isPlaying = value;
    notifyListeners();
  }
  test('clears the shared spectrum when native capture becomes unavailable', () async {
    var captureAvailable = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAudioSpectrum') {
        return captureAvailable ? List<double>.filled(32, 0.8) : <double>[];
      }
      return null;
    });

    final playback = _FakePlayback();
    final visualization = AudioVisualizationProvider()
      ..bindPlayback(
        listenable: playback,
        isPlaying: () => playback.isPlaying,
      );

    playback.setPlaying(true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(visualization.frequencies.any((value) => value > 0), isTrue);

    captureAvailable = false;
    await Future<void>.delayed(const Duration(milliseconds: 140));
    expect(visualization.frequencies.every((value) => value == 0), isTrue);

    visualization.dispose();
  });

}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aetherion.resonate/audio_effects');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAudioSpectrum') {
        return List<double>.filled(32, 0.64);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('forwards mocked native-channel spectrum while playing and clears on pause', () async {
    final playback = _FakePlayback();
    final visualization = AudioVisualizationProvider()
      ..bindPlayback(
        listenable: playback,
        isPlaying: () => playback.isPlaying,
      );

    playback.setPlaying(true);
    await Future<void>.delayed(const Duration(milliseconds: 140));

    expect(visualization.frequencies.any((value) => value > 0), isTrue);

    playback.setPlaying(false);
    expect(visualization.frequencies.every((value) => value == 0), isTrue);

    visualization.dispose();
  });
}
