import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';

/// A simple AudioHandler implementation that bridges just_audio to audio_service.
///
/// This implementation is intentionally minimal but functional for foreground
/// playback and notification updates. It maintains a queue of MediaItems derived
/// from Song objects and propagates playback state and media item changes.
class AudioServiceHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  final List<MediaItem> _items = [];
  ConcatenatingAudioSource? _playlist;

  AudioServiceHandler() {
    // Broadcast queue to clients
    queue.add(_items);

    // Listen to player events and update playback state
    _player.playbackEventStream.listen((event) {
      final playing = _player.playing;
      final processingState = _transformProcessingState(_player.processingState);

      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ));
    });

    // Update current mediaItem when the player changes index
    _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _items.length) {
        mediaItem.add(_items[index]);
      } else {
        mediaItem.add(null);
      }
    });
  }

  // Helper to convert just_audio processing state to audio_service processing
  AudioProcessingState _transformProcessingState(ProcessingState state) {
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
      default:
        return AudioProcessingState.idle;
    }
  }

  // Queue management
  Future<void> addQueueItems(List<Song> songs) async {
    final newItems = songs.map((s) => _songToMediaItem(s)).toList();
    _items.addAll(newItems);
    queue.add(List.unmodifiable(_items));

    // If playlist exists, append sources
    final sources = newItems
        .map((m) => AudioSource.uri(Uri.file(m.extras?['filePath'] ?? '')))
        .toList();

    if (_playlist == null) {
      _playlist = ConcatenatingAudioSource(children: sources);
      await _player.setAudioSource(_playlist!);
    } else {
      await _playlist!.addAll(sources);
    }
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    _items
      ..clear()
      ..addAll(songs.map((s) => _songToMediaItem(s)));
    queue.add(List.unmodifiable(_items));

    _playlist = ConcatenatingAudioSource(
      children: songs
          .map((s) => AudioSource.uri(Uri.file(s.filePath), tag: s.toMap()))
          .toList(),
    );
    await _player.setAudioSource(_playlist!, initialIndex: startIndex);
    if (startIndex >= 0 && startIndex < _items.length) {
      mediaItem.add(_items[startIndex]);
    }
  }

  MediaItem _songToMediaItem(Song s) {
    return MediaItem(
      id: s.id,
      album: s.album,
      title: s.title,
      artist: s.artist,
      duration: s.duration,
      extras: {'filePath': s.filePath, 'albumArt': s.albumArt},
    );
  }

  // Playback controls
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.seekToPrevious();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    _items.add(mediaItem);
    queue.add(List.unmodifiable(_items));
    // append to playlist
    final source = AudioSource.uri(Uri.file(mediaItem.extras?['filePath'] ?? ''), tag: mediaItem.extras);
    if (_playlist == null) {
      _playlist = ConcatenatingAudioSource(children: [source]);
      await _player.setAudioSource(_playlist!);
    } else {
      await _playlist!.add(source);
    }
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = _items.indexWhere((m) => m.id == mediaItem.id);
    if (index >= 0) {
      _items.removeAt(index);
      queue.add(List.unmodifiable(_items));
      if (_playlist != null && index < _playlist!.length) {
        await _playlist!.removeAt(index);
      }
    }
  }

  // Utility: convert MediaItem list to Map<Song> if needed elsewhere

  @override
  Future<void> dispose() async {
    await _player.dispose();
    return super.dispose();
  }
}
