import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/audio_service_handler.dart';

class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;
  final AudioPlayer audioPlayer = AudioPlayer();

  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration? currentDuration;
  double _volume = 1.0;
  List<Song> _queue = [];
  int _queueIndex = 0;

  StreamSubscription<PlaybackState>? _handlerPlaybackSubscription;
  StreamSubscription<MediaItem?>? _handlerMediaItemSubscription;
  StreamSubscription<double>? _handlerVolumeSubscription;

  double get volume => _volume;

  MusicProvider({this.audioHandler}) { _initialize(); }

  void _initialize() {
    if (audioHandler != null) {
      _handlerPlaybackSubscription = audioHandler!.playbackState.listen((state) {
        var changed = false;
        if (isPlaying != state.playing) { isPlaying = state.playing; changed = true; }
        if (currentPosition != state.updatePosition) { currentPosition = state.updatePosition; changed = true; }
        if (changed) notifyListeners();
      });
      _handlerMediaItemSubscription = audioHandler!.mediaItem.listen((item) {
        if (item == null) return;
        currentSong = Song(
          id: item.id,
          title: item.title,
          artist: item.artist ?? 'Unknown Artist',
          album: item.album ?? 'Unknown Album',
          filePath: item.extras?['filePath']?.toString() ?? '',
          duration: item.duration ?? Duration.zero,
          dateAdded: DateTime.now(),
          albumArt: item.extras?['albumArt']?.toString(),
        );
        currentDuration = item.duration;
        notifyListeners();
      });
      if (audioHandler is AudioServiceHandler) {
        _handlerVolumeSubscription = (audioHandler as AudioServiceHandler).volumeStream.listen((value) {
          if (_volume != value) { _volume = value; notifyListeners(); }
        });
      }
      return;
    }

    audioPlayer.playerStateStream.listen((state) { if (isPlaying != state.playing) { isPlaying = state.playing; notifyListeners(); } });
    audioPlayer.positionStream.listen((position) { currentPosition = position; notifyListeners(); });
    audioPlayer.durationStream.listen((duration) { currentDuration = duration; notifyListeners(); });
    audioPlayer.volumeStream.listen((value) { _volume = value; notifyListeners(); });
  }

  Future<void> playSong(Song song) async {
    currentSong = song;
    currentDuration = song.duration;
    notifyListeners();

    if (audioHandler is AudioServiceHandler) {
      final handler = audioHandler as AudioServiceHandler;
      try {
        final existingIndex = _queue.indexWhere((item) => item.id == song.id);
        if (existingIndex >= 0) {
          _queueIndex = existingIndex;
          await handler.setSongQueue(_queue, startIndex: existingIndex);
        } else {
          _queue = [song];
          _queueIndex = 0;
          await handler.setSongQueue(_queue);
        }
        await handler.play();
        return;
      } catch (e) {
        debugPrint('Error playing through AudioService: $e');
        return;
      }
    }

    try {
      await audioPlayer.setAudioSource(AudioSource.uri(_audioUri(song.filePath)));
      await audioPlayer.play();
      isPlaying = true;
      notifyListeners();
    } catch (e) { debugPrint('Error playing song locally: $e'); }
  }

  Uri _audioUri(String value) {
    if (value.startsWith('content://') || value.startsWith('http://') || value.startsWith('https://')) return Uri.parse(value);
    return Uri.file(value);
  }

  Future<void> togglePlayPause() async {
    if (audioHandler != null) {
      if (isPlaying) await audioHandler!.pause(); else await audioHandler!.play();
      return;
    }
    if (audioPlayer.playing) await audioPlayer.pause(); else await audioPlayer.play();
  }

  Future<void> pause() async { if (audioHandler != null) { await audioHandler!.pause(); return; } await audioPlayer.pause(); }

  Future<void> stop() async {
    if (audioHandler != null) {
      await audioHandler!.stop();
      isPlaying = false; currentPosition = Duration.zero; notifyListeners();
      return;
    }
    await audioPlayer.stop(); isPlaying = false; currentPosition = Duration.zero; notifyListeners();
  }

  Future<void> nextSong() async {
    if (audioHandler != null) { await audioHandler!.skipToNext(); return; }
    if (_queue.isNotEmpty && _queueIndex < _queue.length - 1) { _queueIndex++; await playSong(_queue[_queueIndex]); }
  }

  Future<void> previousSong() async {
    if (audioHandler != null) { await audioHandler!.skipToPrevious(); return; }
    if (_queue.isNotEmpty && _queueIndex > 0) { _queueIndex--; await playSong(_queue[_queueIndex]); }
  }

  Future<void> seek(Duration position) async {
    if (audioHandler != null) { await audioHandler!.seek(position); return; }
    await audioPlayer.seek(position);
  }

  Future<void> setVolume(double volume) async {
    final safe = volume.clamp(0.0, 1.0).toDouble();
    if (audioHandler is AudioServiceHandler) {
      await (audioHandler as AudioServiceHandler).setVolume(safe);
    } else {
      await audioPlayer.setVolume(safe);
    }
    _volume = safe;
    notifyListeners();
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    _queue = List<Song>.from(songs);
    if (_queue.isEmpty) { _queueIndex = 0; return; }
    _queueIndex = startIndex.clamp(0, _queue.length - 1);
    if (audioHandler is AudioServiceHandler) {
      await (audioHandler as AudioServiceHandler).setSongQueue(_queue, startIndex: _queueIndex);
      return;
    }
    final sources = _queue.map((song) => AudioSource.uri(_audioUri(song.filePath))).toList();
    await audioPlayer.setAudioSource(ConcatenatingAudioSource(children: sources), initialIndex: _queueIndex);
    currentSong = _queue[_queueIndex];
    currentDuration = currentSong!.duration;
    notifyListeners();
  }

  Stream<Duration?> get durationStream => audioHandler != null
      ? audioHandler!.playbackState.map((_) => currentDuration)
      : audioPlayer.durationStream;

  @override
  void dispose() {
    _handlerPlaybackSubscription?.cancel();
    _handlerMediaItemSubscription?.cancel();
    _handlerVolumeSubscription?.cancel();
    audioPlayer.dispose();
    super.dispose();
  }
}
