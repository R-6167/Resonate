import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resonate/models/song.dart';
import 'package:resonate/modes/models/media_type.dart';
import 'package:resonate/modes/models/mode_media_item.dart';
import 'package:resonate/modes/models/motivation_intent.dart';
import 'package:resonate/modes/models/resonate_mode.dart';
import 'package:resonate/modes/models/work_intent.dart';
import 'package:resonate/modes/providers/mode_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Song makeSong(String id, {String path = '/music/test.mp3'}) => Song(
        id: id, title: 'Test', artist: 'Artist', album: 'Album',
        filePath: path, duration: const Duration(minutes: 3),
        dateAdded: DateTime(2026, 1, 1),
      );

  ModeMediaItem itemFor(Song song) => ModeMediaItem(
        id: song.id, filePath: song.filePath, title: song.title,
        album: song.album, artist: song.artist,
      );

  test('Motivation lifecycle emits session and speech/follow-up intents', () async {
    final modes = ModeProvider();
    await modes.ready;
    await modes.setMode(ResonateMode.motivation);
    final motivation = makeSong('motivation-1', path: '/motivation/motivation.mp3');
    await Future<void>.delayed(Duration.zero);
    modes.onPlaybackStarted(motivation);

    expect(modes.motivationSessionActive, isTrue);
    expect(modes.lastMotivationIntents.any((i) => i.type == MotivationIntentType.sessionStarted), isTrue);
    expect(modes.lastMotivationIntents.any((i) => i.type == MotivationIntentType.speechStarted), isTrue);

    modes.onPlaybackCompleted(motivation);
    expect(modes.lastMotivationIntents.any((i) => i.type == MotivationIntentType.speechCompleted), isTrue);
    expect(modes.lastMotivationIntents.any((i) => i.type == MotivationIntentType.musicFollowupSuggested), isTrue);

    await modes.setMode(ResonateMode.normal);
    expect(modes.motivationSessionActive, isFalse);
    expect(modes.lastMotivationIntents.any((i) => i.type == MotivationIntentType.sessionExited), isTrue);
    modes.dispose();
  });

  test('Work lifecycle follows playback without taking playback authority', () async {
    final modes = ModeProvider();
    await modes.ready;
    await modes.setMode(ResonateMode.work);
    final music = makeSong('music-1');
    modes.onPlaybackStarted(music);
    expect(modes.workSessionActive, isTrue);
    expect(modes.lastWorkIntents.single.type, WorkIntentType.sessionStarted);

    modes.onPlaybackPaused();
    expect(modes.lastWorkIntents.single.type, WorkIntentType.sessionPaused);
    modes.onPlaybackResumed(music);
    expect(modes.lastWorkIntents.single.type, WorkIntentType.sessionResumed);
    modes.onPlaybackStopped();
    expect(modes.lastWorkIntents.single.type, WorkIntentType.sessionCompleted);
    expect(modes.workSessionActive, isFalse);
    modes.dispose();
  });

  test('Mode changes never alter canonical media classification', () async {
    final modes = ModeProvider();
    await modes.ready;
    final music = makeSong('owned', path: '/library/owned.mp3');
    await modes.setMode(ResonateMode.work);
    expect(modes.mediaTypeFor(itemFor(music)), MediaType.music);
    await modes.setMode(ResonateMode.motivation);
    expect(modes.mediaTypeFor(itemFor(music)), MediaType.music);
    modes.dispose();
  });
}
