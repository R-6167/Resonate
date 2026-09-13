import 'package:audio_service/audio_service.dart';

import '../models/song.dart';
import 'playback_authority.dart';
import '../models/song.dart';

/// System-media bridge for Resonate. MusicProvider owns the only AudioPlayers;
/// this service forwards transport commands and mirrors playback state.
class AudioServiceHandler extends BaseAudioHandler with SeekHandler {
  final List<MediaItem> _items = [];
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
  }) {
    if (song != null) {
      final item = songToMediaItem(song);
      mediaItem.add(item);
      _items
        ..clear()
        ..add(item);
      queue.add(List.unmodifiable(_items));
    } else {
      mediaItem.add(null);
      _items.clear();
      queue.add(const <MediaItem>[]);
    }
    playbackState.add(playbackState.value.copyWith(
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
    final orderedSongs = <Song>[
      sourceSongs[requestedIndex],
      ...sourceSongs.take(requestedIndex),
      ...sourceSongs.skip(requestedIndex + 1),
    ];
    _items
      ..clear()
      ..addAll(orderedSongs.map(songToMediaItem));
    queue.add(List.unmodifiable(_items));
    mediaItem.add(_items.first);
  }

  @override
  Future<void> play() async {
    final callback = _onPlay;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'play');
    await callback();
  }

  @override
  Future<void> pause() async {
    final callback = _onPause;
    if (callback == null) return;
    PlaybackAuthority.instance.markExternalUserCommand('audio_service', 'pause');
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

  Future<void> addQueueItem(MediaItem item) async {
    _items.add(item);
    queue.add(List.unmodifiable(_items));
  }

  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    for (final item in mediaItems) {
      await addQueueItem(item);
    }
  }
}
