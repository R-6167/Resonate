import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../database/database_helper.dart';
import '../models/song.dart';
import 'audio_service_handler.dart';

class MusicProvider extends ChangeNotifier {
  late final AudioPlayer _playerA;
  late final AudioPlayer _playerB;
  late final AndroidEqualizer _equalizerA;
  late final AndroidEqualizer _equalizerB;
  late final AndroidLoudnessEnhancer _loudnessA;
  late final AndroidLoudnessEnhancer _loudnessB;

  AudioPlayer get player => _activePlayer;
  AudioPlayer get playerA => _playerA;
  AudioPlayer get playerB => _playerB;

  late AudioPlayer _activePlayer;
  late AudioPlayer _inactivePlayer;
  late AndroidEqualizer _activeEqualizer;
  late AndroidEqualizer _inactiveEqualizer;
  late AndroidLoudnessEnhancer _activeLoudness;
  late AndroidLoudnessEnhancer _inactiveLoudness;

  final DatabaseHelper _database = DatabaseHelper();
  final List<Song> _queue = <Song>[];
  int _queueIndex = -1;
  Song? currentSong;
  bool isPlaying = false;
  bool _crossfadeInProgress = false;
  bool _completionAdvanceInProgress = false;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  Duration position = Duration.zero;
  Duration? duration;
  double volume = 1.0;

  MusicProvider() {
    _equalizerA = AndroidEqualizer();
    _equalizerB = AndroidEqualizer();
    _loudnessA = AndroidLoudnessEnhancer();
    _loudnessB = AndroidLoudnessEnhancer();
    _playerA = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerA, _loudnessA]));
    _playerB = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB, _loudnessB]));
    _activePlayer = _playerA;
    _inactivePlayer = _playerB;
    _activeEqualizer = _equalizerA;
    _inactiveEqualizer = _equalizerB;
    _activeLoudness = _loudnessA;
    _inactiveLoudness = _loudnessB;
    _configureAudioSession();
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  Uri _audioUri(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && (uri.scheme == 'content' || uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'file')) {
      return uri;
    }
    return Uri.file(path);
  }

  void _bindActivePlayerStreams() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();

    _playerStateSubscription = _activePlayer.playerStateStream.listen((state) {
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (isPlaying != playing) {
        isPlaying = playing;
        notifyListeners();
        _publishServiceState();
      }
      if (state.processingState == ProcessingState.completed) {
        isPlaying = false;
        notifyListeners();
        _publishServiceState();
        if (!_completionAdvanceInProgress &&
            !_crossfadeInProgress &&
            _queueIndex >= 0 &&
            _queueIndex < _queue.length - 1) {
          unawaited(_advanceAfterCompletion());
        }
      }
    });

    _positionSubscription = _activePlayer.positionStream.listen((value) {
      position = value;
      notifyListeners();
      _publishServiceState();
    });

    _durationSubscription = _activePlayer.durationStream.listen((value) {
      duration = value;
      notifyListeners();
      _publishServiceState();
    });
  }

  Future<void> _advanceAfterCompletion() async {
    if (_completionAdvanceInProgress) return;
    _completionAdvanceInProgress = true;
    try {
      await nextSong();
    } finally {
      _completionAdvanceInProgress = false;
    }
  }

  Future<void> _stopBoth() async {
    await Future.wait([
      _playerA.stop(),
      _playerB.stop(),
    ]);
    await _playerA.setLoopMode(LoopMode.off);
    await _playerB.setLoopMode(LoopMode.off);
    await _playerA.setVolume(volume);
    await _playerB.setVolume(volume);
  }

  Future<void> _enableEffects(AudioPlayer player, AndroidEqualizer equalizer, AndroidLoudnessEnhancer loudness) async {
    await equalizer.setEnabled(true);
    await loudness.setEnabled(true);
  }

  Future<void> _loadSingle(AudioPlayer player, Song song) async {
    await player.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song));
  }

  Future<void> playSong(Song song, {List<Song>? queue, int? startIndex}) async {
    if (song.filePath.isEmpty) return;
    await _stopBoth();

    currentSong = song;
    if (queue != null) {
      _queue
        ..clear()
        ..addAll(queue);
      _queueIndex = startIndex ?? _queue.indexWhere((item) => item.id == song.id);
      if (_queueIndex < 0) _queueIndex = 0;
    } else {
      _queue
        ..clear()
        ..add(song);
      _queueIndex = 0;
    }

    _activePlayer = _playerA;
    _inactivePlayer = _playerB;
    _activeEqualizer = _equalizerA;
    _inactiveEqualizer = _equalizerB;
    _activeLoudness = _loudnessA;
    _inactiveLoudness = _loudnessB;

    _bindActivePlayerStreams();
    await _activePlayer.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song));
    await _enableEffects(_activePlayer, _activeEqualizer, _activeLoudness);
    await _activePlayer.setVolume(volume);
    await _activePlayer.play();
    isPlaying = true;
    notifyListeners();
    _publishServiceState();
  }

  Future<void> pause() async {
    await _activePlayer.pause();
    isPlaying = false;
    notifyListeners();
    _publishServiceState();
  }

  Future<void> resume() async {
    if (currentSong == null) return;
    await _activePlayer.play();
    isPlaying = true;
    notifyListeners();
    _publishServiceState();
  }

  Future<void> stop() async {
    await _stopBoth();
    isPlaying = false;
    position = Duration.zero;
    notifyListeners();
    _publishServiceState();
  }

  Future<void> seek(Duration value) async {
    await _activePlayer.seek(value);
    position = value;
    notifyListeners();
    _publishServiceState();
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0.0, 1.0);
    await _playerA.setVolume(volume);
    await _playerB.setVolume(volume);
    notifyListeners();
    _publishServiceState();
  }

  Future<void> nextSong() async {
    if (_queueIndex < 0 || _queueIndex >= _queue.length - 1) return;
    final nextIndex = _queueIndex + 1;
    await playSong(_queue[nextIndex], queue: _queue, startIndex: nextIndex);
  }

  Future<void> previousSong() async {
    if (_queueIndex <= 0 || _queueIndex >= _queue.length) return;
    final previousIndex = _queueIndex - 1;
    await playSong(_queue[previousIndex], queue: _queue, startIndex: previousIndex);
  }

  Future<void> enqueueSongs(List<Song> songs) async {
    final existingIds = _queue.map((song) => song.id).toSet();
    for (final song in songs) {
      if (existingIds.add(song.id)) _queue.add(song);
    }
    notifyListeners();
  }

  Future<void> performTrueCrossfade(Song next, {Duration fadeDuration = const Duration(seconds: 5)}) async {
    if (_crossfadeInProgress || currentSong == null || next.filePath.isEmpty) return;
    _crossfadeInProgress = true;
    try {
      final outgoing = _activePlayer;
      final outgoingEqualizer = _activeEqualizer;
      final outgoingLoudness = _activeLoudness;
      final incoming = _inactivePlayer;
      final incomingEqualizer = _inactiveEqualizer;
      final incomingLoudness = _inactiveLoudness;

      await outgoing.setLoopMode(LoopMode.one);
      await incoming.setLoopMode(LoopMode.one);
      await _loadSingle(incoming, next);
      await _enableEffects(incoming, incomingEqualizer, incomingLoudness);
      await incoming.setVolume(0);
      await incoming.play();

      final steps = 20;
      final stepDuration = Duration(microseconds: fadeDuration.inMicroseconds ~/ steps);
      for (var i = 1; i <= steps; i++) {
        final ratio = i / steps;
        await outgoing.setVolume(volume * (1 - ratio));
        await incoming.setVolume(volume * ratio);
        await Future<void>.delayed(stepDuration);
      }

      await outgoing.stop();
      await outgoing.setLoopMode(LoopMode.off);
      await outgoing.setVolume(volume);

      _activePlayer = incoming;
      _inactivePlayer = outgoing;
      _activeEqualizer = incomingEqualizer;
      _inactiveEqualizer = outgoingEqualizer;
      _activeLoudness = incomingLoudness;
      _inactiveLoudness = outgoingLoudness;
      currentSong = next;

      final existingIndex = _queue.indexWhere((song) => song.id == next.id);
      if (existingIndex >= 0) {
        _queueIndex = existingIndex;
      } else {
        _queue.insert(_queueIndex + 1, next);
        _queueIndex += 1;
      }

      _bindActivePlayerStreams();
      isPlaying = true;
      notifyListeners();
      _publishServiceState();
    } finally {
      _crossfadeInProgress = false;
    }
  }

  void _publishServiceState() {
    try {
      AudioServiceHandler.instance?.publishFromProvider(this);
    } catch (_) {
      // Audio service is optional during startup/tests.
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerA.dispose();
    _playerB.dispose();
    super.dispose();
  }
}
