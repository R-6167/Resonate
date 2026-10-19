import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/services/lyrics_service.dart';

void main() {
  group('LyricsService.parseLrc', () {
    test('parses and sorts timed lines', () {
      final lines = LyricsService.parseLrc(
        '[ar:Artist]\n[00:12.34]Second line\n[00:02.5]First line',
      );
      expect(lines, hasLength(2));
      expect(lines[0].text, 'First line');
      expect(lines[0].timestamp, const Duration(seconds: 2, milliseconds: 500));
      expect(lines[1].text, 'Second line');
      expect(lines[1].timestamp, const Duration(seconds: 12, milliseconds: 340));
    });

    test('expands multiple timestamps on a single line', () {
      final lines = LyricsService.parseLrc('[00:01.00][00:03.00]Repeat');
      expect(lines.map((line) => line.timestamp!.inSeconds), [1, 3]);
      expect(lines.map((line) => line.text), ['Repeat', 'Repeat']);
    });

    test('ignores metadata, empty lines, and malformed tags', () {
      expect(LyricsService.parseLrc('[ti:Song]\n[00:02.00]\nnot a timestamp'), isEmpty);
    });
  });
}
