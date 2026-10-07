import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/modes/models/media_type.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/models/mode_media_item.dart';
import 'package:resonate/modes/providers/mode_provider.dart';
import 'package:resonate/modes/services/audiobook_session_bridge.dart';

class _Modes extends ModeProvider {
  @override
  MediaType mediaTypeFor(ModeMediaItem item) => MediaType.audiobook;
}

Song _book() => Song(
      id: 'book-1',
      title: 'Chapter One',
      artist: 'Author',
      album: 'Book',
      filePath: '/media/audiobooks/book-1.m4b',
      duration: const Duration(hours: 1),
      dateAdded: DateTime(2026, 10, 1),
    );

void main() {
  final t0 = DateTime(2026, 10, 7, 10);
  final position = const Duration(minutes: 18, seconds: 20);

  test('starts audiobook session only for classified audiobook in Audiobook mode', () {
    final modes = _Modes();
    final bridge = AudiobookSessionBridge();

    bridge.onSongStarted(
      modes: modes,
      song: _book(),
      resumePosition: position,
    );

    expect(modes.mode, ResonateMode.normal);
    expect(bridge.isActive, isFalse);

    modes.setMode(ResonateMode.audiobook);
    bridge.onSongStarted(
      modes: modes,
      song: _book(),
      resumePosition: position,
    );

    expect(bridge.isActive, isTrue);
    expect(bridge.coordinator.lastKnownPosition, position);
  });

  test('pause, resume and completion follow host playback lifecycle', () {
    final modes = _Modes()..setMode(ResonateMode.audiobook);
    final bridge = AudiobookSessionBridge();

    bridge.onSongStarted(modes: modes, song: _book());
    bridge.onPaused(position);

    expect(bridge.coordinator.isPaused, isTrue);
    expect(bridge.coordinator.lastKnownPosition, position);

    bridge.onResumed(position);
    expect(bridge.coordinator.isPaused, isFalse);

    bridge.onCompleted(position);
    expect(bridge.isActive, isFalse);
  });

  test('mode exit stops audiobook session without filtering the song itself', () {
    final modes = _Modes()..setMode(ResonateMode.audiobook);
    final bridge = AudiobookSessionBridge();
    bridge.onSongStarted(modes: modes, song: _book());

    modes.setMode(ResonateMode.normal);
    bridge.sync(
      modes: modes,
      song: _book(),
      position: position,
      playing: true,
    );

    expect(bridge.isActive, isFalse);
  });
}
