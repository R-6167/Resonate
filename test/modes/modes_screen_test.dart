import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate_modes_lab/modes/providers/mode_provider.dart';
import 'package:resonate_modes_lab/modes/screens/modes_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('reference Modes screen renders the active mode and folder controls',
      (tester) async {
    final provider = ModeProvider();
    await provider.ready;

    await tester.pumpWidget(
      ChangeNotifierProvider<ModeProvider>.value(
        value: provider,
        child: const MaterialApp(home: ModesScreen()),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Active:'), findsOneWidget);
    expect(find.textContaining('Normal'), findsWidgets);
    expect(find.text('Content folders'), findsOneWidget);
    expect(find.text('Podcast'), findsOneWidget);
    expect(find.text('Motivation'), findsOneWidget);
    expect(find.text('Audiobook'), findsOneWidget);

    provider.dispose();
  });
}
