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
    final path = song.filePath.trim();
    if (path.isEmpty) {
      debugPrint('Cannot play song: empty file path for ${song.title}');
      isPlaying = false;
      notifyListeners();
      return;
    }

    currentSong = song;
    currentDuration = song.duration;
    isPlaying = false;
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
      } catch (e, stack) {
        isPlaying = false;
        debugPrint('Error playing through AudioService: $e');
        debugPrint('$stack');
        notifyListeners();
        return;
      }
    }

    try {
      await audioPlayer.setAudioSource(AudioSource.uri(_audioUri(path)));
      await audioPlayer.play();
      isPlaying = true;
      notifyListeners();
    } catch (e, stack) {
      isPlaying = false;
      debugPrint('Error playing song locally: $e');
      debugPrint('$stack');
      notifyListeners();
    }
  }

  Uri _audioUri(String value) {
    if (value.startsWith('content://') || value.startsWith('http://') || value.startsWith('https://')) return Uri.parse(value);
    return Uri.file(value);
  }

  Future<void> togglePlayPause() async {
    try {
      if (audioHandler != null) {
        if (isPlaying) await audioHandler!.pause(); else await audioHandler!.play();
        return;
      }
      if (audioPlayer.playing) await audioPlayer.pause(); else await audioPlayer.play();
    } catch (e) {
      debugPrint('Playback toggle failed: $e');
      isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pause() async { try { if (audioHandler != null) { await audioHandler!.pause(); return; } await audioPlayer.pause(); } catch (e) { debugPrint('Pause failed: $e'); } }

  Future<void> stop() async {
    try {
      if (audioHandler != null) {
        await audioHandler!.stop();
        isPlaying = false; currentPosition = Duration.zero; notifyListeners();
        return;
      }
      await audioPlayer.stop(); isPlaying = false; currentPosition = Duration.zero; notifyListeners();
    } catch (e) { debugPrint('Stop failed: $e'); }
  }

  Future<void> nextSong() async { try { if (audioHandler != null) { await audioHandler!.skipToNext(); return; } if (_queue.isNotEmpty && _queueIndex < _queue.length - 1) { _queueIndex++; await playSong(_queue[_queueIndex]); } } catch (e) { debugPrint('Next song failed: $e'); } }

  Future<void> previousSong() async { try { if (audioHandler != null) { await audioHandler!.skipToPrevious(); return; } if (_queue.isNotEmpty && _queueIndex > 0) { _queueIndex--; await playSong(_queue[_queueIndex]); } } catch (e) { debugPrint('Previous song failed: $e'); } }

  Future<void> seek(Duration position) async { try { if (audioHandler != null) { await audioHandler!.seek(position); return; } await audioPlayer.seek(position); } catch (e) { debugPrint('Seek failed: $e'); } }

  Future<void> setVolume(double volume) async {
    final safe = volume.clamp(0.0, 1.0).toDouble();
    try {
      if (audioHandler is AudioServiceHandler) await (audioHandler as AudioServiceHandler).setVolume(safe); else await audioPlayer.setVolume(safe);
      _volume = safe;
      notifyListeners();
    } catch (e) { debugPrint('Volume change failed: $e'); }
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    _queue = List<Song>.from(songs);
    if (_queue.isEmpty) { _queueIndex = 0; return; }
    _queueIndex = startIndex.clamp(0, _queue.length - 1);
    try {
      if (audioHandler is AudioServiceHandler) {
        await (audioHandler as AudioServiceHandler).setSongQueue(_queue, startIndex: _queueIndex);
        return;
      }
      final sources = _queue.map((song) => AudioSource.uri(_audioUri(song.filePath))).toList();
      await audioPlayer.setAudioSource(ConcatenatingAudioSource(children: sources), initialIndex: _queueIndex);
      currentSong = _queue[_queueIndex];
      currentDuration = currentSong!.duration;
      notifyListeners();
    } catch (e, stack) {
      debugPrint('Queue setup failed: $e');
      debugPrint('$stack');
      isPlaying = false;
      notifyListeners();
    }
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
