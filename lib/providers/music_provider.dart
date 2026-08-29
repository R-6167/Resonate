import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';

class MusicProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  Song? _current;
  bool _isPlaying = false;

  MusicProvider() {
    _init();
  }

  Song? get currentSong => _current;
  bool get isPlaying => _isPlaying;
  AudioPlayer get player => _player;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player.playbackEventStream.listen((event) {
      final playing = _player.playing;
      if (playing != _isPlaying) {
        _isPlaying = playing;
        notifyListeners();
      }
    });
  }

  Future<void> playSong(Song song) async {
    try {
      _current = song;
      await _player.setFilePath(song.path);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing song: $e');
    }
  }

  Future<void> playPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _current = null;
    notifyListeners();
  }

  Future<void> setCrossfade(Duration duration) async {
    try {
      await _player.setCrossFadeEnabled(true);
      await _player.setCrossfadeDuration(duration);
    } catch (e) {
      debugPrint('Crossfade not supported or error: $e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
