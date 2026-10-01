#!/usr/bin/env python3
"""MediaSession hardening: accurate processing state, yield publish, no optimistic play."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ash_path = ROOT / "lib/services/audio_service_handler.dart"
music_path = ROOT / "lib/providers/music_provider.dart"


def patch_handler() -> None:
    t = ash_path.read_text()
    if "publishYielded" in t and "AudioProcessingState.paused" in t:
        print("handler: already hardened")
        return

    # Fix processingState in publishPlayback
    old_ps = "      processingState: song == null ? AudioProcessingState.idle : AudioProcessingState.ready,\n"
    new_ps = (
        "      processingState: song == null\n"
        "          ? AudioProcessingState.idle\n"
        "          : (playing ? AudioProcessingState.ready : AudioProcessingState.paused),\n"
    )
    if old_ps not in t:
        raise SystemExit("handler: processingState line miss")
    t = t.replace(old_ps, new_ps, 1)
    print("handler: processingState ready/paused/idle")

    # publishPositionTick should also set processingState when playing changes
    old_tick = """    playbackState.add(playbackState.value.copyWith(
      controls: [MediaControl.skipToPrevious, playing ? MediaControl.pause : MediaControl.play, MediaControl.skipToNext],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward, MediaAction.skipToNext, MediaAction.skipToPrevious, MediaAction.play, MediaAction.pause, MediaAction.stop},
      androidCompactActionIndices: const [0, 1, 2],
      playing: playing,
      updatePosition: position,
      bufferedPosition: bufferedPosition ?? position,
      speed: speed <= 0 ? 1.0 : speed,
    ));
"""
    new_tick = """    final hasItem = mediaItem.value != null;
    playbackState.add(playbackState.value.copyWith(
      controls: [MediaControl.skipToPrevious, playing ? MediaControl.pause : MediaControl.play, MediaControl.skipToNext],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward, MediaAction.skipToNext, MediaAction.skipToPrevious, MediaAction.play, MediaAction.pause, MediaAction.stop},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: !hasItem
          ? AudioProcessingState.idle
          : (playing ? AudioProcessingState.ready : AudioProcessingState.paused),
      playing: playing,
      updatePosition: position,
      bufferedPosition: bufferedPosition ?? position,
      speed: speed <= 0 ? 1.0 : speed,
    ));
"""
    if old_tick in t:
        t = t.replace(old_tick, new_tick, 1)
        print("handler: position tick processingState")
    else:
        print("WARNING: position tick block miss")

    # publishYielded method before songToMediaItem
    if "void publishYielded" not in t:
        yield_fn = '''
  /// Force MediaSession into a non-playing paused state after exclusive focus loss.
  /// Bypasses position-tick throttling so other apps see an honest session immediately.
  void publishYielded({Duration? position}) {
    final pos = position ?? playbackState.value.position;
    _lastPlaying = false;
    _lastPositionPublish = DateTime.now();
    final hasItem = mediaItem.value != null;
    playbackState.add(playbackState.value.copyWith(
      controls: const [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState:
          hasItem ? AudioProcessingState.paused : AudioProcessingState.idle,
      playing: false,
      updatePosition: pos,
      bufferedPosition: pos,
      speed: 1.0,
    ));
  }

'''
        if "  MediaItem songToMediaItem" in t:
            t = t.replace(
                "  MediaItem songToMediaItem",
                yield_fn + "  MediaItem songToMediaItem",
                1,
            )
            print("handler: publishYielded added")
        else:
            raise SystemExit("handler: songToMediaItem anchor miss")

    # Remove optimistic playing:true on play()
    old_play = """  Future<void> play() async {
    final callback = _onPlay;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'play');
    publishPositionTick(playing: true, position: playbackState.value.position, force: true);
    await callback();
  }
"""
    new_play = """  Future<void> play() async {
    final callback = _onPlay;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'play');
    // Do not optimistically set playing:true — wait for MusicProvider to publish
    // after the engine actually starts (avoids fighting other apps for focus).
    await callback();
  }
"""
    if old_play in t:
        t = t.replace(old_play, new_play, 1)
        print("handler: no optimistic play")
    else:
        print("WARNING: play() block miss")

    ash_path.write_text(t)


def patch_music() -> None:
    t = music_path.read_text()

    # _publishServiceState: force not playing while focus suspended
    old_pub = """  void _publishServiceState({bool positionOnly = false}) {
    final handler = audioHandler;
    if (handler is! AudioServiceHandler) return;
    Duration pos = currentPosition;
    Duration? buffered;
    try { pos = audioPlayer.position; buffered = audioPlayer.bufferedPosition; } catch (_) { buffered = currentPosition; }
    if (positionOnly) {
      handler.publishPositionTick(playing: isPlaying, position: pos, bufferedPosition: buffered, speed: 1.0);
      return;
    }
    handler.publishPlayback(song: currentSong, playing: isPlaying, position: pos, duration: currentDuration ?? currentSong?.duration, speed: 1.0, bufferedPosition: buffered, playbackQueue: _queue, queueIndex: _queueIndex);
  }
"""
    new_pub = """  void _publishServiceState({bool positionOnly = false}) {
    final handler = audioHandler;
    if (handler is! AudioServiceHandler) return;
    Duration pos = currentPosition;
    Duration? buffered;
    try { pos = audioPlayer.position; buffered = audioPlayer.bufferedPosition; } catch (_) { buffered = currentPosition; }
    // While focus is yielded, never advertise playing to MediaSession.
    final sessionPlaying = isPlaying && !_focusSuspended;
    if (positionOnly) {
      if (_focusSuspended) {
        handler.publishYielded(position: pos);
        return;
      }
      handler.publishPositionTick(playing: sessionPlaying, position: pos, bufferedPosition: buffered, speed: 1.0);
      return;
    }
    if (_focusSuspended) {
      handler.publishYielded(position: pos);
      return;
    }
    handler.publishPlayback(
      song: currentSong,
      playing: sessionPlaying,
      position: pos,
      duration: currentDuration ?? currentSong?.duration,
      speed: 1.0,
      bufferedPosition: buffered,
      playbackQueue: _queue,
      queueIndex: _queueIndex,
    );
  }
"""
    if old_pub in t:
        t = t.replace(old_pub, new_pub, 1)
        print("music: publish respects suspension")
    else:
        print("WARNING: _publishServiceState miss")

    # _yieldToExternalAudio: call publishYielded explicitly
    if "publishYielded" not in t.split("_yieldToExternalAudio")[1][:800] if "_yieldToExternalAudio" in t else True:
        old_y = """    isPlaying = false;
    await _abandonAudioFocus(reason: reason);
    _publishServiceState();
    notifyListeners();
"""
        new_y = """    isPlaying = false;
    await _abandonAudioFocus(reason: reason);
    // Honest MediaSession immediately (paused, not ready/playing).
    final handler = audioHandler;
    if (handler is AudioServiceHandler) {
      Duration pos = currentPosition;
      try {
        pos = audioPlayer.position;
      } catch (_) {}
      handler.publishYielded(position: pos);
    } else {
      _publishServiceState();
    }
    notifyListeners();
"""
        if old_y in t:
            t = t.replace(old_y, new_y, 1)
            print("music: yield publishes MediaSession paused")
        else:
            print("WARNING: yield publish block miss")

    music_path.write_text(t)


def main() -> None:
    patch_handler()
    patch_music()
    print("mediasession hardening done")


if __name__ == "__main__":
    main()
