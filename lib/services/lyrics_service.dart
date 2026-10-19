import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/song.dart';

class LyricLine {
  const LyricLine({required this.text, this.timestamp});
  final String text;
  final Duration? timestamp;
}

class LyricsDocument {
  const LyricsDocument({required this.lines, required this.isTimed, required this.sourcePath});
  final List<LyricLine> lines;
  final bool isTimed;
  final String sourcePath;
  bool get isEmpty => lines.isEmpty;
}

/// Reads same-folder .lrc (timed) or .txt (plain) lyrics without network access.
class LyricsService {
  const LyricsService();

  Future<LyricsDocument?> loadForSong(Song song) async {
    try {
      final audio = File(song.filePath);
      final directory = p.dirname(audio.path);
      final basename = p.basenameWithoutExtension(audio.path);
      final lrc = File(p.join(directory, '$basename.lrc'));
      if (await lrc.exists()) {
        final lines = parseLrc(await lrc.readAsString());
        if (lines.isNotEmpty) {
          return LyricsDocument(lines: lines, isTimed: true, sourcePath: lrc.path);
        }
      }
      final txt = File(p.join(directory, '$basename.txt'));
      if (await txt.exists()) {
        final lines = (await txt.readAsString())
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trimRight())
            .where((line) => line.trim().isNotEmpty)
            .map((line) => LyricLine(text: line))
            .toList(growable: false);
        if (lines.isNotEmpty) {
          return LyricsDocument(lines: lines, isTimed: false, sourcePath: txt.path);
        }
      }
    } catch (_) {
      // Lyrics are optional: unreadable or content-backed paths must not affect audio.
      return null;
    }
    return null;
  }

  /// Parses common LRC timestamps, including multiple timestamps per line.
  static List<LyricLine> parseLrc(String input) {
    final output = <LyricLine>[];
    final pattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    for (final rawLine in input.split(RegExp(r'\r?\n'))) {
      final matches = pattern.allMatches(rawLine).toList(growable: false);
      if (matches.isEmpty) continue;
      final text = rawLine.substring(matches.last.end).trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
        final fraction = match.group(3) ?? '';
        final millis = fraction.isEmpty
            ? 0
            : int.parse(fraction.padRight(3, '0').substring(0, 3));
        output.add(LyricLine(
          timestamp: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
          text: text,
        ));
      }
    }
    output.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
    return List<LyricLine>.unmodifiable(output);
  }
}
