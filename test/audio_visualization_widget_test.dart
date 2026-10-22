import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:resonate/providers/audio_visualization_provider.dart';
import 'package:resonate/widgets/audio_visualization_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('visualizer repaints from spectrum changes without a motion timer',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AudioVisualizationProvider();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AudioVisualizationProvider>.value(
        value: settings,
        child: const MaterialApp(
          home: Scaffold(body: AudioVisualizationWidget()),
        ),
      ),
    );

    final firstPainter =
        tester.widget<CustomPaint>(find.byKey(const ValueKey('audio-spectrum-painter'))).painter!;
    settings.frequencies = List<double>.filled(32, 0.0);
    settings.notifyListeners();
    await tester.pump();
    final silentPainter =
        tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;

    settings.frequencies = List<double>.generate(32, (i) => (i + 1) / 32);
    settings.notifyListeners();
    await tester.pump();
    final audioPainter =
        tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;

    expect(audioPainter.shouldRepaint(silentPainter), isTrue);
    expect(firstPainter, isNot(same(audioPainter)));

    // With no provider updates, pumping time alone must not change the painter:
    // all motion now comes from the native spectrum, not an independent ticker.
    await tester.pump(const Duration(seconds: 1));
    final settledPainter =
        tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;
    expect(identical(audioPainter, settledPainter), isTrue);
    expect(tester.takeException(), isNull);
  });
}
