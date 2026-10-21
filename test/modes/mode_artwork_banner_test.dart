import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/widgets/mode_artwork_banner.dart';

void main() {
  testWidgets('each mode banner uses its matching bundled image and label',
      (tester) async {
    const expectedAssets = <ResonateMode, String>{
      ResonateMode.normal: 'assets/Normal_Mode.jpg',
      ResonateMode.running: 'assets/Running_Mode.jpg',
      ResonateMode.workout: 'assets/Workout_Mode.jpg',
      ResonateMode.driving: 'assets/Driving_Mode.jpg',
      ResonateMode.work: 'assets/Work_Mode.jpg',
      ResonateMode.podcast: 'assets/Podcast_Mode.jpg',
      ResonateMode.motivation: 'assets/Motivation_Mode.jpg',
      ResonateMode.audiobook: 'assets/Audiobook_Mode.jpg',
      ResonateMode.sleep: 'assets/Sleep_Mode.jpg',
    };

    for (final entry in expectedAssets.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModeArtworkBanner(mode: entry.key),
          ),
        ),
      );
      expect(find.text(entry.key.label.toUpperCase()), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName, entry.value);
      expect(image.fit, BoxFit.cover);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('banner stays within narrow layout with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(12),
              child: ModeArtworkBanner(mode: ResonateMode.motivation),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('MOTIVATION'), findsOneWidget);
  });
}
