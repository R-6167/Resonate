import 'dart:async';
import 'dart:math';

import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

typedef PlayerSongCallback = FutureOr<void> Function(Song song);
typedef PlayerStateCallback = void Function(bool playing);
typedef PlayerPositionCallback = void Function(Duration position);
typedef PlayerDurationCallback = void Function(Duration? duration);

/// Clean playback core for Resonate.
///
/// This class intentionally owns exactly one AudioPlayer. Queue navigation,
/// repeat and shuffle are state-machine concerns here; UI/providers only issue
/// commands. No crossfade, EQ, normalization or Intelligence logic belongs in
/// this core.
class RemasteredPlayerEngine {
  final AudioPlayer player;

  final List<Song> _queue = <Song>[];
  int _index = -1;
  bool _shuffle = false;
  bool _repeatOne = false;
  bool _repeatAll = false;
  bool _transitioning = false;
  int _transitionToken = 0;
  double _volume = 1.0;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  PlayerSongCallback? onSongChanged;
  PlayerStateCallback? onPlayingChanged;
  PlayerPositionCallback? onPositionChanged;
  PlayerDurationCallback? onDurationChanged;
  FutureOr<void> Function()? onCompleted;

  RemasteredPlayerEngine({AudioPlayer? audioPlayer})
      : player = audioPlayer ?? AudioPlayer() {
    _stateSub = player.playerStateStream.listen(_handlePlayerState);
    _positionSub = player.positionStream.listen((position) {
      onPositionChanged?.call(position);
    });
    _durationSub = player.durationStream.listen((duration) {
      onDurationChanged?.call(duration);
    });
  }

  List<Song> get queue => List.unmodifiable(_queue);
  int get index => _index;
  Song? get currentSong => _index >= 0 && _index < _queue.length ? _queue[_index] : null;
  bool get isPlaying => player.playing;
  bool get shuffleEnabled => _shuffle;
  bool get repeatOne => _repeatOne;
  bool get repeatAll => _repeatAll;
  double get volume => _volume;

  List<Song> get upcoming => _index < 0
      ? List.unmodifiable(_queue)
      : List.unmodifiable(_queue.skip(_index + 1));

  void setShuffle(bool enabled) {
    if (_shuffle == enabled) return;
    _shuffle = enabled;
    if (!enabled || _queue.length < 2 || _index < 0) return;

    final current = _queue[_index];
    final before = _queue.take(_index).toList();
    final after = _queue.skip(_index + 1).toList()..shuffle(Random());
    _queue
      ..clear()
      ..addAll(before)
      ..add(current)
      ..addAll(after);
  }

  void setRepeat({required bool one, required bool all}) {
    _repeatOne = one;
    _repeatAll = !one && all;
  }

  Future<bool> setQueue(
    List<Song> songs, {
    int startIndex = 0,
    bool autoplay = true,
  }) async {
    final valid = songs.where((song) => song.filePath.trim().isNotEmpty).toList();
    if (valid.isEmpty) {
      await stop();
      _queue.clear();
      _index = -1;
      return false;
    }

    final safeIndex = startIndex.clamp(0, valid.length - 1).toInt();
    _queue
      ..clear()
      ..addAll(valid);
    _index = safeIndex;
    return _loadCurrent(autoplay: autoplay);
  }

  Future<bool> playSong(
    Song song, {
    List<Song>? queue,
    int startIndex = 0,
    bool autoplay = true,
  }) async {
    if (song.filePath.trim().isEmpty) return false;

    final source = queue == null || queue.isEmpty ? <Song>[song] : queue.toList();
    final selected = source.indexWhere((item) => item.id == song.id);
    final requestedIndex = selected >= 0 ? selected : startIndex;
    return setQueue(source, startIndex: requestedIndex, autoplay: autoplay);
  }

  Future<bool> _loadCurrent({required bool autoplay}) async {
    final song = currentSong;
    if (song == null) return false;

    final token = ++_transitionToken;
    _transitioning = true;
    try {
      await player.stop();
      if (token != _transitionToken) return false;
      await player.setLoopMode(LoopMode.off);
      await player.setVolume(_volume);
      await player.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song));
      if (token != _transitionToken) return false;
      await onSongChanged?.call(song);
      if (autoplay) {
        await player.play();
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      if (token == _transitionToken) _transitioning = false;
    }
  }

  Future<void> play() async {
    if (player.audioSource != null) {
      await player.play();
      return;
    }
    if (currentSong != null) await _loadCurrent(autoplay: true);
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> stop() async {
    ++_transitionToken;
    _transitioning = false;
    await player.stop();
  }

  Future<void> seek(Duration position) async {
    final duration = player.duration ?? currentSong?.duration;
    var target = position;
    if (target.isNegative) target = Duration.zero;
    if (duration != null && target > duration) target = duration;
    await player.seek(target);
  }

  Future<bool> next() async {
    if (_queue.isEmpty || _transitioning) return false;
    if (_index >= _queue.length - 1) {
      if (!_repeatAll) return false;
      _index = 0;
    } else {
      _index++;
    }
    return _loadCurrent(autoplay: true);
  }

  Future<bool> previous() async {
    if (_queue.isEmpty || _transitioning) return false;
    final position = player.position;
    if (position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return true;
    }
    if (_index <= 0) {
      await player.seek(Duration.zero);
      return true;
    }
    _index--;
    return _loadCurrent(autoplay: true);
  }

  Future<bool> playNext(Song song) async {
    if (song.filePath.trim().isEmpty || _queue.any((item) => item.id == song.id)) return false;
    final insertAt = (_index + 1).clamp(0, _queue.length).toInt();
    _queue.insert(insertAt, song);
    return true;
  }

  Future<bool> addToQueue(Song song) async {
    if (song.filePath.trim().isEmpty || _queue.any((item) => item.id == song.id)) return false;
    _queue.add(song);
    return true;
  }

  Future<bool> removeFromQueue(int index) async {
    if (index <= _index || index >= _queue.length) return false;
    _queue.removeAt(index);
    return true;
  }

  Future<bool> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex <= _index || oldIndex >= _queue.length) return false;
    if (newIndex > oldIndex) newIndex--;
    newIndex = newIndex.clamp(_index + 1, _queue.length - 1).toInt();
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    return true;
  }

  void clearUpcoming() {
    if (_index < 0 || _index >= _queue.length - 1) return;
    _queue.removeRange(_index + 1, _queue.length);
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0).toDouble();
    await player.setVolume(_volume);
  }

  void _handlePlayerState(PlayerState state) {
    onPlayingChanged?.call(state.playing && state.processingState != ProcessingState.completed);
    if (state.processingState == ProcessingState.completed) {
      unawaited(_handleCompletion());
    }
  }

  Future<void> _handleCompletion() async {
    if (_transitioning || _queue.isEmpty) return;
    if (_repeatOne) {
      await player.seek(Duration.zero);
      await player.play();
      return;
    }
    final advanced = await next();
    if (!advanced) {
      await onCompleted?.call();
    }
  }

  Uri _audioUri(String value) {
    final path = value.trim();
    if (path.startsWith('content://') ||
        path.startsWith('file://') ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return Uri.parse(path);
    }
    return Uri.file(path);
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await player.dispose();
  }
}
