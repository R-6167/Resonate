import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/listening_event.dart';
import '../services/audio_service_handler.dart';
import '../services/database_helper.dart';
import '../services/playback_authority.dart';
import '../services/playback_intent_gate.dart';
import '../services/resonate_diagnostics.dart';
import '../services/library_visibility_store.dart';
import '../services/audio_effects_bridge.dart';
import '../services/audio_effects_controller.dart';
import '../services/playback_coordinator.dart';

enum PlaybackRepeatMode { off, all, one }

// TEMPORARY STUB - full file restore in progress. Do not use this build.
// Please revert music_provider.dart to commit a845b7282469c9184c2f1d3fc8a94ef5996c2bbe
class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;
  MusicProvider({this.audioHandler});
  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration? currentDuration;
  double get volume => 1.0;
  List<Song> get queue => const [];
  int get queueIndex => 0;
  List<Song> get upcomingQueue => const [];
  bool get shuffleEnabled => false;
  PlaybackRepeatMode get repeatMode => PlaybackRepeatMode.off;
  bool get canCrossfadeNext => false;
  bool get crossfadeEnabled => false;
  int get crossfadeDurationMs => 3000;
  String get crossfadeFadeType => 'linear';
  String get activeEngineLabel => 'A';
  bool get transitionInProgress => false;
  late final dynamic audioPlayer;
  late final dynamic equalizer;
  late final dynamic loudnessEnhancer;
  Future<void> setShuffleEnabled(bool enabled) async {}
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}
  Future<void> setCrossfadeEnabled(bool enabled) async {}
  Future<void> setCrossfadeDuration(int milliseconds) async {}
  Future<void> setCrossfadeFadeType(String value) async {}
  Future<void> syncSavedAudioEffects() async {}
  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0}) async => false;
  Future<bool> enqueueSongs(List<Song> songs) async => false;
  Future<bool> addToQueue(Song song) async => false;
  Future<bool> playNext(Song song) async => false;
  Future<bool> removeFromQueue(int index) async => false;
  Future<bool> reorderQueue(int oldIndex, int newIndex) async => false;
  void clearUpcomingQueue() {}
  Future<bool> performTrueCrossfade({required int milliseconds, String fadeType = 'linear'}) async => false;
  Future<void> togglePlayPause({String source = 'normal_player'}) async {}
  Future<void> pause({String source = 'normal_player'}) async {}
  Future<void> stop({String source = 'normal_player'}) async {}
  Future<void> nextSong({String source = 'normal_player'}) async {}
  Future<void> previousSong({String source = 'normal_player'}) async {}
  Future<void> seek(Duration position, {String source = 'normal_player'}) async {}
  Future<void> setVolume(double volume) async {}
  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {}
  Stream<Duration?> get durationStream => const Stream.empty();
}
