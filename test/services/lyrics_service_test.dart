import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
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

  group('LyricsService.loadForSong', () {
    late Directory directory;
    late Song song;
    const service = LyricsService();

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('resonate_lyrics_test_');
      final audioPath = '${directory.path}/Sample Track.mp3';
      await File(audioPath).writeAsBytes(<int>[0]);
      song = Song(
        id: 'test-song',
        title: 'Sample Track',
        artist: 'Test Artist',
        album: 'Test Album',
        filePath: audioPath,
        duration: Duration.zero,
        dateAdded: DateTime(2026),
      );
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('loads matching timed LRC sidecar', () async {
      await File('${directory.path}/Sample Track.lrc')
          .writeAsString('[00:00.00]Opening line\n[00:04.00]Next line');
      final result = await service.loadForSong(song);
      expect(result, isNotNull);
      expect(result!.isTimed, isTrue);
      expect(result.lines.map((line) => line.text), ['Opening line', 'Next line']);
    });

    test('loads plain text sidecar when no usable LRC exists', () async {
      await File('${directory.path}/Sample Track.txt').writeAsString('First line\n\nSecond line\n');
      final result = await service.loadForSong(song);
      expect(result, isNotNull);
      expect(result!.isTimed, isFalse);
      expect(result.lines.map((line) => line.text), ['First line', 'Second line']);
    });

    test('returns null when lyrics are missing', () async {
      expect(await service.loadForSong(song), isNull);
    });
  });
}
