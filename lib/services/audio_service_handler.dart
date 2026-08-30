import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

/// AudioHandler used by Resonate.
///
/// Bridges just_audio with audio_service so playback can continue
/// while the app is in the background and media controls can be
/// displayed by Android.
class AudioServiceHandler extends BaseAudioHandler
    with
        SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  final List<MediaItem> _items = [];

  ConcatenatingAudioSource? _playlist;

  StreamSubscription<PlaybackEvent>? _playbackSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;

  AudioServiceHandler() {
    _initializeListeners();
  }

  // ---------------------------------------------------------------------------
  // INITIALIZATION
  // ---------------------------------------------------------------------------

  void _initializeListeners() {
    // Initial queue.
    queue.add(List.unmodifiable(_items));

    // Playback state.
    _playbackSubscription =
        _player.playbackEventStream.listen((event) {
      final playing = _player.playing;

      final processingState =
          _transformProcessingState(
        _player.processingState,
      );

      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing)
              MediaControl.pause
            else
              MediaControl.play,
            MediaControl.stop,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [
            0,
            1,
            3,
          ],
          processingState: processingState,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
        ),
      );
    });

    // Current media item.
    _currentIndexSubscription =
        _player.currentIndexStream.listen((index) {
      if (index != null &&
          index >= 0 &&
          index < _items.length) {
        mediaItem.add(_items[index]);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // PROCESSING STATE
  // ---------------------------------------------------------------------------

  AudioProcessingState _transformProcessingState(
    ProcessingState state,
  ) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;

      case ProcessingState.loading:
        return AudioProcessingState.loading;

      case ProcessingState.buffering:
        return AudioProcessingState.buffering;

      case ProcessingState.ready:
        return AudioProcessingState.ready;

      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  // ---------------------------------------------------------------------------
  // SONG -> MEDIA ITEM
  // ---------------------------------------------------------------------------

  MediaItem songToMediaItem(Song song) {
    return MediaItem(
      id: song.id,
      album: song.album,
      title: song.title,
      artist: song.artist,
      duration: song.duration,
      extras: {
        'filePath': song.filePath,
        'albumArt': song.albumArt,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SONG QUEUE
  // ---------------------------------------------------------------------------

  /// Custom Resonate method for adding Song objects.
  ///
  /// This is deliberately NOT named addQueueItems because
  /// BaseAudioHandler already defines addQueueItems(List<MediaItem>).
  Future<void> addSongsToQueue(List<Song> songs) async {
    final mediaItems =
        songs.map(songToMediaItem).toList();

    for (final item in mediaItems) {
      await addQueueItem(item);
    }
  }

  /// Sets the entire Resonate queue.
  Future<void> setSongQueue(
    List<Song> songs, {
    int startIndex = 0,
  }) async {
    _items
      ..clear()
      ..addAll(
        songs.map(songToMediaItem),
      );

    queue.add(
      List.unmodifiable(_items),
    );

    final sources = songs.map(
      (song) {
        return AudioSource.uri(
          Uri.file(song.filePath),
          tag: songToMediaItem(song),
        );
      },
    ).toList();

    if (sources.isEmpty) {
      _playlist = null;
      await _player.stop();
      mediaItem.add(null);
      return;
    }

    _playlist = ConcatenatingAudioSource(
      children: sources,
    );

    final safeStartIndex =
        startIndex.clamp(0, sources.length - 1);

    await _player.setAudioSource(
      _playlist!,
      initialIndex: safeStartIndex,
    );

    mediaItem.add(
      _items[safeStartIndex],
    );
  }

  // ---------------------------------------------------------------------------
  // AUDIO SERVICE QUEUE API
  // ---------------------------------------------------------------------------

  @override
  Future<void> addQueueItem(
    MediaItem mediaItem,
  ) async {
    _items.add(mediaItem);

    queue.add(
      List.unmodifiable(_items),
    );

    final filePath =
        mediaItem.extras?['filePath']?.toString();

    if (filePath == null || filePath.isEmpty) {
      return;
    }

    final source = AudioSource.uri(
      Uri.file(filePath),
      tag: mediaItem,
    );

    if (_playlist == null) {
      _playlist = ConcatenatingAudioSource(
        children: [source],
      );

      await _player.setAudioSource(
        _playlist!,
      );
    } else {
      await _playlist!.add(source);
    }
  }

  @override
  Future<void> addQueueItems(
    List<MediaItem> mediaItems,
  ) async {
    for (final item in mediaItems) {
      await addQueueItem(item);
    }
  }

  @override
  Future<void> removeQueueItem(
    MediaItem mediaItem,
  ) async {
    final index = _items.indexWhere(
      (item) => item.id == mediaItem.id,
    );

    if (index < 0) {
      return;
    }

    _items.removeAt(index);

    queue.add(
      List.unmodifiable(_items),
    );

    if (_playlist != null &&
        index < _playlist!.length) {
      await _playlist!.removeAt(index);
    }

    if (_items.isEmpty) {
      mediaItem = mediaItem;
    }
  }

  // ---------------------------------------------------------------------------
  // PLAYBACK CONTROLS
  // ---------------------------------------------------------------------------

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();

    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState:
            AudioProcessingState.idle,
        updatePosition: Duration.zero,
      ),
    );

    await super.stop();
  }

  @override
  Future<void> seek(
    Duration position,
  ) async {
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_playlist == null ||
        _playlist!.length == 0) {
      return;
    }

    try {
      await _player.seekToNext();
    } catch (e) {
      // Nothing to do if already at the last track.
      print('Unable to skip to next: $e');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playlist == null ||
        _playlist!.length == 0) {
      return;
    }

    try {
      await _player.seekToPrevious();
    } catch (e) {
      print('Unable to skip to previous: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // VOLUME
  // ---------------------------------------------------------------------------

  Future<void> setVolume(double volume) async {
    await _player.setVolume(
      volume.clamp(0.0, 1.0),
    );
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  /// BaseAudioHandler does not expose dispose(), so this
  /// must NOT use @override or super.dispose().
  Future<void> dispose() async {
    await _playbackSubscription?.cancel();
    await _currentIndexSubscription?.cancel();
    await _player.dispose();
  }
}
