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
}
