import 'package:audio_service/audio_service.dart';

import '../models/song.dart';
import 'playback_authority.dart';

/// System-media bridge for Resonate. MusicProvider owns the only AudioPlayers;
/// this service forwards transport commands and mirrors playback state.
class AudioServiceHandler extends BaseAudioHandler with SeekHandler {
  final List<MediaItem> _items = [];
  String? _lastMediaItemId;
  bool? _lastPlaying;
  DateTime _lastPositionPublish = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> Function()? _onPlay;
  Future<void> Function()? _onPause;
  Future<void> Function()? _onStop;
  Future<void> Function(Duration)? _onSeek;
  Future<void> Function()? _onNext;
  Future<void> Function()? _onPrevious;

  AudioServiceHandler();

  void bindPlaybackController({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onStop,
    required Future<void> Function(Duration) onSeek,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) {
    _onPlay = onPlay;
    _onPause = onPause;
    _onStop = onStop;
    _onSeek = onSeek;
    _onNext = onNext;
    _onPrevious = onPrevious;
  }

  void publishPlayback({
    required Song? song,
    required bool playing,
    required Duration position,
    required Duration? duration,
    required double speed,
    Duration? bufferedPosition,
    List<Song>? playbackQueue,
    int queueIndex = 0,
  }) {
    // Only publish a small window around the current track. Publishing the
    // entire library (100+ MediaItems) on low-RAM devices can kill the UI
    // while ExoPlayer keeps playing ("app keeps stopping").
    final full = (playbackQueue ?? (song == null ? const <Song>[] : <Song>[song]))
        .where((item) => item.filePath.trim().isNotEmpty)
        .toList();
    List<Song> window;
    int windowIndex;
    if (full.isEmpty) {
      window = const <Song>[];
      windowIndex = 0;
    } else {
      final center = queueIndex.clamp(0, full.length - 1);
      final start = (center - 8).clamp(0, full.length - 1);
      final end = (center + 9).clamp(0, full.length); // exclusive
      window = full.sublist(start, end);
      windowIndex = (center - start).clamp(0, window.length - 1);
    }
    final sourceQueue = window.map(songToMediaItem).toList();
    if (sourceQueue.isNotEmpty) {
      _items
        ..clear()
        ..addAll(sourceQueue);
      queue.add(List.unmodifiable(_items));
    } else {
      _lastMediaItemId = null;
      mediaItem.add(null);
      _items.clear();
      queue.add(const <MediaItem>[]);
    }
    if (sourceQueue.isNotEmpty && _items.isNotEmpty) {
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


  MediaItem songToMediaItem(Song song) {
    final art = song.albumArt?.trim() ?? '';
    Uri? artUri;
    if (art.isNotEmpty) {
      if (art.startsWith('content://') ||
          art.startsWith('file://') ||
          art.startsWith('http://') ||
          art.startsWith('https://')) {
        artUri = Uri.parse(art);
      } else {
        artUri = Uri.file(art);
      }
    }
    return MediaItem(
      id: song.id,
      album: song.album,
      title: song.title,
      artist: song.artist,
      duration: song.duration,
      playable: true,
      artUri: artUri,
      extras: {'filePath': song.filePath, 'albumArt': song.albumArt},
    );
  }

  Future<void> setSongQueue(List<Song> songs, {int startIndex = 0}) async {
    final sourceSongs = songs.where((song) => song.filePath.trim().isNotEmpty).toList();
    if (sourceSongs.isEmpty) {
      _items.clear();
      queue.add(const <MediaItem>[]);
      mediaItem.add(null);
      return;
    }
    final requestedIndex = startIndex.clamp(0, sourceSongs.length - 1);
    _items
      ..clear()
      ..addAll(sourceSongs.map(songToMediaItem));
    queue.add(List.unmodifiable(_items));
    mediaItem.add(_items[requestedIndex]);
  }

  @override
  Future<void> play() async {
    final callback = _onPlay;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'play');
    publishPositionTick(playing: true, position: playbackState.value.position, force: true);
    await callback();
  }

  @override
  Future<void> pause() async {
    final callback = _onPause;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'pause');
    publishPositionTick(playing: false, position: playbackState.value.position, force: true);
    await callback();
  }

  @override
  Future<void> stop() async {
    final callback = _onStop;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'stop');
    await callback();
  }

  @override
  Future<void> seek(Duration position) async {
    final callback = _onSeek;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'seek');
    publishPositionTick(playing: playbackState.value.playing, position: position, force: true);
    await callback(position);
  }

  @override
  Future<void> fastForward() async {
    final current = playbackState.value.position;
    final duration = mediaItem.value?.duration;
    final target = duration == null
        ? current + const Duration(seconds: 10)
        : (current + const Duration(seconds: 10)).compareTo(duration) > 0
            ? duration
            : current + const Duration(seconds: 10);
    await seek(target);
  }

  @override
  Future<void> rewind() async {
    final current = playbackState.value.position;
    final target = current > const Duration(seconds: 10)
        ? current - const Duration(seconds: 10)
        : Duration.zero;
    await seek(target);
  }

  @override
  Future<void> skipToNext() async {
    final callback = _onNext;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'next');
    await callback();
  }

  @override
  Future<void> skipToPrevious() async {
    final callback = _onPrevious;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'previous');
    await callback();
  }

}
