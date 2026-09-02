import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

class AudioServiceHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final List<MediaItem> _items = [];
  ConcatenatingAudioSource? _playlist;
  StreamSubscription<PlaybackEvent>? _playbackSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;

  AudioServiceHandler() {
    _initializeListeners();
  }

  void _initializeListeners() {
    queue.add(List.unmodifiable(_items));

    _playbackSubscription = _player.playbackEventStream.listen((event) {
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: _transformProcessingState(_player.processingState),
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ));
    });

    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _items.length) {
        mediaItem.add(_items[index]);
      }
    });
  }

  AudioProcessingState _transformProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle: return AudioProcessingState.idle;
      case ProcessingState.loading: return AudioProcessingState.loading;
      case ProcessingState.buffering: return AudioProcessingState.buffering;
      case ProcessingState.ready: return AudioProcessingState.ready;
      case ProcessingState.completed: return AudioProcessingState.completed;
    }
  }

  MediaItem songToMediaItem(Song song) => MediaItem(
    id: song.id,
    album: song.album,
    title: song.title,
    artist: song.artist,
    duration: song.duration,
    extras: {'filePath': song.filePath, 'albumArt': song.albumArt},
  );

  Uri _audioUri(String value) {
    if (value.startsWith('content://') || value.startsWith('http://') || value.startsWith('https://')) return Uri.parse(value);
    return Uri.file(value);
  }

  Future<void> setSongQueue(List<Song> songs, {int startIndex = 0}) async {
    _items..clear()..addAll(songs.map(songToMediaItem));
    queue.add(List.unmodifiable(_items));
    final sources = songs.map((song) => AudioSource.uri(_audioUri(song.filePath), tag: songToMediaItem(song))).toList();
    if (sources.isEmpty) {
      _playlist = null;
      await _player.stop();
      mediaItem.add(null);
      return;
    }
    _playlist = ConcatenatingAudioSource(children: sources);
    final safeIndex = startIndex.clamp(0, sources.length - 1);
    try {
      await _player.setAudioSource(_playlist!, initialIndex: safeIndex);
      mediaItem.add(_items[safeIndex]);
    } catch (e) {
      playbackState.add(playbackState.value.copyWith(processingState: AudioProcessingState.error));
      rethrow;
    }
  }

  @override
  Future<void> addQueueItem(MediaItem item) async {
    _items.add(item);
    queue.add(List.unmodifiable(_items));
    final filePath = item.extras?['filePath']?.toString();
    if (filePath == null || filePath.isEmpty) return;
    final source = AudioSource.uri(_audioUri(filePath), tag: item);
    if (_playlist == null) {
      _playlist = ConcatenatingAudioSource(children: [source]);
      await _player.setAudioSource(_playlist!);
      mediaItem.add(item);
    } else {
      await _playlist!.add(source);
    }
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    for (final item in mediaItems) await addQueueItem(item);
  }

  @override
  Future<void> removeQueueItem(MediaItem item) async {
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) return;
    _items.removeAt(index);
    queue.add(List.unmodifiable(_items));
    if (_playlist != null && index < _playlist!.length) await _playlist!.removeAt(index);
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(playing: false, processingState: AudioProcessingState.idle, updatePosition: Duration.zero));
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> skipToNext() async { if (_playlist != null && _playlist!.length > 0) await _player.seekToNext(); }
  @override
  Future<void> skipToPrevious() async { if (_playlist != null && _playlist!.length > 0) await _player.seekToPrevious(); }

  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));
  Stream<double> get volumeStream => _player.volumeStream;
  Stream<int?> get audioSessionIdStream => _player.androidAudioSessionIdStream;

  Future<void> dispose() async {
    await _playbackSubscription?.cancel();
    await _currentIndexSubscription?.cancel();
    await _player.dispose();
  }
}
