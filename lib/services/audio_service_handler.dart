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

  Future<void> Function()? _onPlay;
  Future<void> Function()? _onPause;
  Future<void> Function()? _onStop;
  Future<void> Function(Duration)? _onSeek;
  Future<void> Function()? _onNext;
  Future<void> Function()? _onPrevious;

  AudioServiceHandler() { _initializeListeners(); }

  /// Connects Android notification/media-button commands to Resonate's
  /// foreground MusicProvider. This avoids maintaining a second playback path.
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
  }) {
    if (song != null) {
      final item = songToMediaItem(song);
      mediaItem.add(item);
      if (_items.isEmpty || _items.first.id != item.id) {
        _items..clear()..add(item);
        queue.add(List.unmodifiable(_items));
      }
    }
    playbackState.add(playbackState.value.copyWith(
      controls: [MediaControl.skipToPrevious, playing ? MediaControl.pause : MediaControl.play, MediaControl.stop, MediaControl.skipToNext],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 3],
      processingState: song == null ? AudioProcessingState.idle : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: position,
      speed: speed,
    ));
  }

  void _initializeListeners() {
    queue.add(List.unmodifiable(_items));
    _playbackSubscription = _player.playbackEventStream.listen((event) {
      playbackState.add(playbackState.value.copyWith(
        controls: [MediaControl.skipToPrevious, _player.playing ? MediaControl.pause : MediaControl.play, MediaControl.stop, MediaControl.skipToNext],
        systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
        androidCompactActionIndices: const [0, 1, 3],
        processingState: _transformProcessingState(_player.processingState),
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
      ));
    });
    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _items.length) mediaItem.add(_items[index]);
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

  MediaItem songToMediaItem(Song song) {
    final art = song.albumArt?.trim() ?? '';
    Uri? artUri;
    if (art.isNotEmpty) {
      if (art.startsWith('content://') || art.startsWith('file://') || art.startsWith('http://') || art.startsWith('https://')) artUri = Uri.parse(art);
      else artUri = Uri.file(art);
    }
    return MediaItem(id: song.id, album: song.album, title: song.title, artist: song.artist, duration: song.duration, playable: true, artUri: artUri, extras: {'filePath': song.filePath, 'albumArt': song.albumArt});
  }

  Uri _audioUri(String value) {
    final path = value.trim();
    if (path.startsWith('content://') || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('file://')) return Uri.parse(path);
    return Uri.file(path);
  }

  Future<void> setSongQueue(List<Song> songs, {int startIndex = 0}) async {
    final sourceSongs = songs.where((song) => song.filePath.trim().isNotEmpty).toList();
    if (sourceSongs.isEmpty) { _items.clear(); queue.add(const []); _playlist = null; await _player.stop(); mediaItem.add(null); return; }
    final requestedIndex = startIndex.clamp(0, sourceSongs.length - 1);
    final orderedSongs = <Song>[sourceSongs[requestedIndex], ...sourceSongs.take(requestedIndex), ...sourceSongs.skip(requestedIndex + 1)];
    _items..clear()..addAll(orderedSongs.map(songToMediaItem));
    queue.add(List.unmodifiable(_items));
    try {
      await _player.stop();
      _playlist = ConcatenatingAudioSource(children: [AudioSource.uri(_audioUri(orderedSongs.first.filePath), tag: songToMediaItem(orderedSongs.first))], useLazyPreparation: true);
      await _player.setAudioSource(_playlist!, initialIndex: 0);
      mediaItem.add(_items.first);
      for (final song in orderedSongs.skip(1)) { try { await _playlist!.add(AudioSource.uri(_audioUri(song.filePath), tag: songToMediaItem(song))); } catch (_) {} }
    } catch (e) {
      _playlist = null;
      playbackState.add(playbackState.value.copyWith(playing: false, processingState: AudioProcessingState.error));
      rethrow;
    }
  }

  @override Future<void> addQueueItem(MediaItem item) async { final filePath = item.extras?['filePath']?.toString().trim(); if (filePath == null || filePath.isEmpty) return; _items.add(item); queue.add(List.unmodifiable(_items)); final source = AudioSource.uri(_audioUri(filePath), tag: item); if (_playlist == null) { _playlist = ConcatenatingAudioSource(children: [source], useLazyPreparation: true); await _player.setAudioSource(_playlist!); mediaItem.add(item); } else await _playlist!.add(source); }
  @override Future<void> addQueueItems(List<MediaItem> mediaItems) async { for (final item in mediaItems) { await addQueueItem(item); } }
  @override Future<void> removeQueueItem(MediaItem item) async { final index = _items.indexWhere((candidate) => candidate.id == item.id); if (index < 0) return; _items.removeAt(index); queue.add(List.unmodifiable(_items)); if (_playlist != null && index < _playlist!.length) await _playlist!.removeAt(index); }
  @override Future<void> play() async { if (_onPlay != null) return _onPlay!(); if (_playlist == null || _playlist!.length == 0) return; await _player.play(); }
  @override Future<void> pause() async { if (_onPause != null) return _onPause!(); await _player.pause(); }
  @override Future<void> stop() async { if (_onStop != null) return _onStop!(); await _player.stop(); playbackState.add(playbackState.value.copyWith(playing: false, processingState: AudioProcessingState.idle, updatePosition: Duration.zero)); await super.stop(); }
  @override Future<void> seek(Duration position) async { if (_onSeek != null) return _onSeek!(position); if (_playlist == null || _playlist!.length == 0) return; await _player.seek(position); }
  @override Future<void> skipToNext() async { if (_onNext != null) return _onNext!(); final index = _player.currentIndex; if (_playlist == null || index == null || index >= _playlist!.length - 1) return; await _player.seekToNext(); }
  @override Future<void> skipToPrevious() async { if (_onPrevious != null) return _onPrevious!(); final index = _player.currentIndex; if (_playlist == null || index == null || index <= 0) return; await _player.seekToPrevious(); }
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));
  Stream<double> get volumeStream => _player.volumeStream;
  Stream<int?> get audioSessionIdStream => _player.androidAudioSessionIdStream;
  Future<void> dispose() async { await _playbackSubscription?.cancel(); await _currentIndexSubscription?.cancel(); await _player.dispose(); }
}
