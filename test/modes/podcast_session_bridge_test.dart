import 'package:flutter_test/flutter_test.dart';

import '../../lib/models/song.dart';
import '../../lib/modes/models/media_type.dart';
import '../../lib/modes/models/mode_media_item.dart';
import '../../lib/modes/models/resonate_mode.dart';
import '../../lib/modes/providers/mode_provider.dart';
import '../../lib/modes/services/podcast_session_bridge.dart';

void main() {
  group('PodcastSessionBridge', () {
    final t0 = DateTime(2026, 10, 6, 10);

    Song song(String id) => Song(
      id: id,
      title: id,
      artist: 'Artist',
      album: 'Album',
      filePath: '/podcasts/$id.mp3',
      duration: const Duration(minutes: 40),
      dateAdded: t0,
    );

    Future<ModeProvider> podcastModes() async {
      final modes = ModeProvider();
      await modes.ready;
      await modes.setMode(ResonateMode.podcast);
      await modes.setUserMediaType(
        ModeMediaItem(
          id: 'episode',
          filePath: '/podcasts/episode.mp3',
          title: 'episode',
          album: 'Album',
          artist: 'Artist',
        ),
        MediaType.podcast,
      );
      return modes;
    }

    test('starts a podcast session only in Podcast Mode', () async {
      final modes = await podcastModes();
      final bridge = PodcastSessionBridge();
      bridge.onSongStarted(
        modes: modes,
        song: song('episode'),
        resumePosition: const Duration(minutes: 5),
      );
      expect(bridge.isActive, isTrue);
      expect(bridge.coordinator.lastKnownPosition, const Duration(minutes: 5));
    });

    test('normal Library playback is not gated by the bridge', () async {
      final modes = ModeProvider();
      await modes.ready;
      await modes.setMode(ResonateMode.normal);
      final bridge = PodcastSessionBridge();
      bridge.onSongStarted(modes: modes, song: song('episode'));
      expect(bridge.isActive, isFalse);
    });

    test('pause, resume and completion follow host lifecycle', () async {
      final modes = await podcastModes();
      final bridge = PodcastSessionBridge();
      bridge.onSongStarted(modes: modes, song: song('episode'));
      bridge.onPaused(const Duration(minutes: 8));
      expect(bridge.coordinator.isPaused, isTrue);
      bridge.onResumed(const Duration(minutes: 8));
      expect(bridge.coordinator.isPaused, isFalse);
      bridge.onCompleted(const Duration(minutes: 40));
      expect(bridge.isActive, isFalse);
    });
  });
}
