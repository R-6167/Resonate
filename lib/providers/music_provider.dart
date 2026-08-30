import 'package:flutter/material.dart';

class MusicProvider extends ChangeNotifier {
  // Minimal stub for music control
  bool isPlaying = false;
  String? currentSongId;

  void play(String songId) {
    currentSongId = songId;
    isPlaying = true;
    notifyListeners();
  }

  void pause() {
    isPlaying = false;
    notifyListeners();
  }

  void stop() {
    isPlaying = false;
    currentSongId = null;
    notifyListeners();
  }
}
