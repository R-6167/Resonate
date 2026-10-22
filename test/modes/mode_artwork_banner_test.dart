import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/widgets/mode_artwork_banner.dart';

void main() {
  testWidgets('mode banners keep photographs reserved for Now Playing',
      (tester) async {
    for (final mode in ResonateMode.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModeArtworkBanner(mode: mode),
          ),
        ),
      );
      expect(find.text(mode.label.toUpperCase()), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('${mode.label} mode artwork')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
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
