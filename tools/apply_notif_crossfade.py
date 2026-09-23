#!/usr/bin/env python3
from pathlib import Path

h = Path("lib/services/audio_service_handler.dart")
ht = h.read_text()
if "publishPositionTick" not in ht:
    ht = ht.replace(
        "  final List<MediaItem> _items = [];\n  Future<void> Function()? _onPlay;",
        "  final List<MediaItem> _items = [];\n  String? _lastMediaItemId;\n  bool? _lastPlaying;\n  DateTime _lastPositionPublish = DateTime.fromMillisecondsSinceEpoch(0);\n  Future<void> Function()? _onPlay;",
    )
    ht = ht.replace(
        "      final safeIndex = windowIndex.clamp(0, _items.length - 1);\n      mediaItem.add(_items[safeIndex]);\n    } else {\n      mediaItem.add(null);\n      _items.clear();\n      queue.add(const <MediaItem>[]);\n    }\n",
        "    } else {\n      _lastMediaItemId = null;\n      mediaItem.add(null);\n      _items.clear();\n      queue.add(const <MediaItem>[]);\n    }\n",
    )
    old = """    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.rewind,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 2, 4],
      processingState: song == null
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: bufferedPosition ?? position,
      speed: speed,
    ));
  }"""
    new = """    if (sourceQueue.isNotEmpty && _items.isNotEmpty) {
      final safeIndex = windowIndex.clamp(0, _items.length - 1);
      final nextItem = _items[safeIndex];
      if (_lastMediaItemId != nextItem.id) {
        _lastMediaItemId = nextItem.id;
        mediaItem.add(nextItem);
      }
    }
    _lastPlaying = playing;
    _lastPositionPublish = DateTime.now();
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward,
        MediaAction.skipToNext, MediaAction.skipToPrevious, MediaAction.play, MediaAction.pause, MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: song == null ? AudioProcessingState.idle : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: bufferedPosition ?? position,
      speed: speed <= 0 ? 1.0 : speed,
      queueIndex: sourceQueue.isEmpty ? null : windowIndex,
    ));
  }

  void publishPositionTick({required bool playing, required Duration position, Duration? bufferedPosition, double speed = 1.0, bool force = false}) {
    final now = DateTime.now();
    if (!force && _lastPlaying == playing && now.difference(_lastPositionPublish) < const Duration(milliseconds: 400)) return;
    _lastPlaying = playing;
    _lastPositionPublish = now;
    playbackState.add(playbackState.value.copyWith(
      controls: [MediaControl.skipToPrevious, playing ? MediaControl.pause : MediaControl.play, MediaControl.skipToNext],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward, MediaAction.skipToNext, MediaAction.skipToPrevious, MediaAction.play, MediaAction.pause, MediaAction.stop},
      androidCompactActionIndices: const [0, 1, 2],
      playing: playing,
      updatePosition: position,
      bufferedPosition: bufferedPosition ?? position,
      speed: speed <= 0 ? 1.0 : speed,
    ));
  }
"""
    if old not in ht: raise SystemExit('controls missing')
    ht = ht.replace(old, new, 1)
    ht = ht.replace(
        "PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'play');\n    await callback();",
        "PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'play');\n    publishPositionTick(playing: true, position: playbackState.value.position, force: true);\n    await callback();",
        1,
    )
    ht = ht.replace(
        "PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'pause');\n    await callback();",
        "PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'pause');\n    publishPositionTick(playing: false, position: playbackState.value.position, force: true);\n    await callback();",
        1,
    )
    ht = ht.replace(
        "PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'seek');\n    await callback(position);",
        "PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'seek');\n    publishPositionTick(playing: playbackState.value.playing, position: position, force: true);\n    await callback(position);",
        1,
    )
    h.write_text(ht)
    print('handler OK')

m = Path('lib/main.dart')
mt = m.read_text()
if 'androidStopForegroundOnPause: false' not in mt:
    mt = mt.replace('androidStopForegroundOnPause: true,', "androidStopForegroundOnPause: false,\n      androidNotificationChannelDescription: 'Now playing and transport controls',\n      fastForwardInterval: Duration(seconds: 10),\n      rewindInterval: Duration(seconds: 10),", 1)
    m.write_text(mt)
    print('main OK')

mp = Path('lib/providers/music_provider.dart')
t = mp.read_text()
if 'positionOnly' not in t:
    old = "  void _publishServiceState() { final handler = audioHandler; if (handler is AudioServiceHandler) handler.publishPlayback(song: currentSong, playing: isPlaying, position: currentPosition, duration: currentDuration, speed: 1.0, bufferedPosition: audioPlayer.bufferedPosition, playbackQueue: _queue, queueIndex: _queueIndex); }"
    new = """  void _publishServiceState({bool positionOnly = false}) {
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
  }"""
    if old not in t: raise SystemExit('publish missing')
    t = t.replace(old, new, 1)
    t = t.replace(
        "        notifyListeners();\n        _publishServiceState();\n      }\n      _maybeStartAutomaticCrossfade(position);",
        "        notifyListeners();\n        _publishServiceState(positionOnly: true);\n      }\n      _maybeStartAutomaticCrossfade(position);",
        1,
    )
    print('publish OK')

if 'startMarginMs = 1800' not in t:
    t = t.replace(
        'final startMarginMs = 1400;\n    final triggerMs = (_crossfadeDurationMs + startMarginMs).clamp(1200, 14000);',
        'final startMarginMs = 1800;\n    final triggerMs = (_crossfadeDurationMs + startMarginMs).clamp(1500, 15000);',
    )
    print('margin OK')

if 'await Future<void>.delayed(const Duration(milliseconds: 60));' not in t:
    t = t.replace(
        "      if (!incomingStarted) {\n        _preloadedNextSongId = null;\n        throw StateError('crossfade incoming engine failed to start');\n      }\n      // Start from the *current* outgoing level",
        "      if (!incomingStarted) {\n        _preloadedNextSongId = null;\n        throw StateError('crossfade incoming engine failed to start');\n      }\n      await Future<void>.delayed(const Duration(milliseconds: 60));\n      try { if (!incoming.playing) incoming.play(); } catch (_) {}\n      // Start from the *current* outgoing level",
        1,
    )
    print('settle OK')

mp.write_text(t)
assert 'publishPositionTick' in h.read_text()
assert 'positionOnly' in mp.read_text()
print('ALL OK')
