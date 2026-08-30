import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import '../models/song.dart';

class MusicProvider extends ChangeNotifier {
  final AudioPlayer audioPlayer = AudioPlayer();
  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  List<Song> _queue = [];
  int _queueIndex = 0;

  MusicProvider() {
    audioPlayer.playerStateStream.listen((state) {
      final playing = state.playing;
      if (isPlaying != playing) {
        isPlaying = playing;
        notifyListeners();
      }
    });

    audioPlayer.positionStream.listen((pos) {
      currentPosition = pos;
      notifyListeners();
    });

    audioPlayer.durationStream.listen((d) {
      // duration updates handled in UI via stream from audioPlayer
      notifyListeners();
    });
  }

  Future<void> playSong(Song song) async {
    try {
      if (currentSong?.id != song.id) {
        await audioPlayer.setAudioSource(AudioSource.uri(Uri.file(song.filePath)));
        currentSong = song;
      }
      await audioPlayer.play();
      isPlaying = true;
      notifyListeners();
    } catch (e) {
      // Log but don't crash
      print('Error playing song: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (audioPlayer.playing) {
      await audioPlayer.pause();
      isPlaying = false;
    } else {
      await audioPlayer.play();
      isPlaying = true;
    }
    notifyListeners();
  }

  Future<void> pause() async {
    await audioPlayer.pause();
    isPlaying = false;
    notifyListeners();
  }

  Future<void> stop() async {
    await audioPlayer.stop();
    isPlaying = false;
    currentSong = null;
    currentPosition = Duration.zero;
    notifyListeners();
  }

  Future<void> nextSong() async {
    if (_queue.isNotEmpty && _queueIndex < _queue.length - 1) {
      _queueIndex++;
      await playSong(_queue[_queueIndex]);
    }
  }

  Future<void> previousSong() async {
    if (_queue.isNotEmpty && _queueIndex > 0) {
      _queueIndex--;
      await playSong(_queue[_queueIndex]);
    }
  }

  Future<void> seek(Duration position) async {
    await audioPlayer.seek(position);
    currentPosition = position;
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    await audioPlayer.setVolume(v.clamp(0.0, 1.0));
    notifyListeners();
  }

  // Queue management
  void setQueue(List<Song> songs, {int startIndex = 0}) {
    _queue = List.from(songs);
    _queueIndex = startIndex;
  }

  Stream<Duration?> get durationStream => audioPlayer.durationStream;
}
