import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/widgets/mode_artwork_banner.dart';

void main() {
  group('ModeArtworkBanner', () {
    testWidgets('renders every supported mode with an accessible label',
        (tester) async {
      for (final mode in ResonateMode.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeArtworkBanner(mode: mode),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(mode.label.toUpperCase()), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('${mode.label} mode artwork')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('does not overflow on a narrow screen with large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: ModeArtworkBanner(mode: ResonateMode.audiobook),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AUDIOBOOK'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
  testWidgets('keeps supplied photographs out of mode picker banners',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ModeArtworkBanner(mode: ResonateMode.running),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('uses the matching supplied photograph for the player backdrop',
      (tester) async {
    for (final mode in ResonateMode.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModeArtworkBackground(mode: mode),
          ),
        ),
      );

      final expectedAsset = switch (mode) {
        ResonateMode.normal => 'assets/Normal_Mode_Light.jpg',
        ResonateMode.running => 'assets/Running_Mode_Light.jpg',
        ResonateMode.workout => 'assets/Workout_Mode_Light.jpg',
        ResonateMode.driving => 'assets/Driving_Mode_Light.jpg',
        ResonateMode.work => 'assets/Work_Mode_Light.jpg',
        ResonateMode.podcast => 'assets/Podcast_Mode_Light.jpg',
        ResonateMode.motivation => 'assets/Motivation_Mode_Light.jpg',
        ResonateMode.audiobook => 'assets/Audiobook_Mode_Light.jpg',
        ResonateMode.sleep => 'assets/Sleep_Mode_Light.jpg',
      };

      expect(find.byType(Image), findsAtLeastNWidgets(1));
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.image, isA<ResizeImage>());
      expect(
        ((image.image as ResizeImage).imageProvider as AssetImage).assetName,
        expectedAsset,
      );
      expect(image.fit, BoxFit.cover);
      expect(
        find.bySemanticsLabel('${mode.label} mode background'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('requests dark-theme artwork when the app theme is dark',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: ModeArtworkBackground(mode: ResonateMode.normal),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image).first);
    final provider = image.image as ResizeImage;
    expect(
      (provider.imageProvider as AssetImage).assetName,
      'assets/Normal_Mode_Dark.jpg',
    );
    expect(tester.takeException(), isNull);
  });

}
