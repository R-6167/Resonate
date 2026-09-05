import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listening_event.dart';
import '../models/song.dart';
import '../services/audio_service_handler.dart';
import '../services/database_helper.dart';
import '../services/remastered_player_engine.dart';

enum PlaybackRepeatMode { off, all, one }

/// UI-facing facade for the new Resonate playback core.
///
/// The old dual-player/crossfade state machine is deliberately gone from this
/// branch. This provider owns app state/history and delegates real playback to
/// one deterministic RemasteredPlayerEngine.
class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;
  final DatabaseHelper _database = DatabaseHelper();
  late final RemasteredPlayerEngine _engine;

  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration? currentDuration;
  double _volume = 1.0;
  List<Song> _queue = <Song>[];
  int _queueIndex = -1;
  bool _shuffleEnabled = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;

  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 3000;
  String _crossfadeFadeType = 'linear';

  ListeningEvent? _activeHistoryEvent;
  int _activeHistoryPositionMs = 0;
  DateTime? _lastResumePersist;
  Future<void> _historySerial = Future<void>.value();

  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;

  static const _savedQueueIdsKey = 'playback_queue_song_ids';
  static const _savedQueueIndexKey = 'playback_queue_index';
  static const _shuffleEnabledKey = 'playback_shuffle_enabled';
  static const _repeatModeKey = 'playback_repeat_mode';
  static const _crossfadeEnabledKey = 'crossfade_enabled';
  static const _crossfadeDurationKey = 'crossfade_duration';
  static const _crossfadeFadeTypeKey = 'crossfade_fade_type';
  static const _resumePositionKey = 'playback_resume_position_ms';
  static const _resumeSongIdKey = 'playback_resume_song_id';

  int _resumePositionMs = 0;
  String? _resumeSongId;

  MusicProvider({this.audioHandler}) {
    _engine = RemasteredPlayerEngine();
    _engine.onSongChanged = _handleEngineSongChanged;
    _engine.onPlayingChanged = (playing) {
      if (isPlaying == playing) return;
      isPlaying = playing;
      _publishServiceState();
      notifyListeners();
    };
    _engine.onPositionChanged = (position) {
      currentPosition = position;
      if (_activeHistoryEvent != null) {
        _activeHistoryPositionMs = position.inMilliseconds;
        _persistResumePosition();
      }
      _publishServiceState();
      notifyListeners();
    };
    _engine.onDurationChanged = (duration) {
      if (duration != null) currentDuration = duration;
      _publishServiceState();
      notifyListeners();
    };
    _engine.onCompleted = () async {
      isPlaying = false;
      currentPosition = currentDuration ?? currentPosition;
      await _finishHistoryEvent(completed: true);
      _publishServiceState();
      notifyListeners();
    };

    if (audioHandler is AudioServiceHandler) {
      (audioHandler! as AudioServiceHandler).bindPlaybackController(
        onPlay: togglePlayPause,
        onPause: pause,
        onStop: stop,
        onSeek: seek,
        onNext: nextSong,
        onPrevious: previousSong,
      );
    }

    unawaited(_configureAudioSession());
    unawaited(_loadPlaybackSettings());
    unawaited(_restoreQueue());
  }

  AudioPlayer get audioPlayer => _engine.player;
  List<Song> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  List<Song> get upcomingQueue => _queueIndex < 0
      ? List.unmodifiable(_queue)
      : List.unmodifiable(_queue.skip(_queueIndex + 1));
  bool get shuffleEnabled => _shuffleEnabled;
  PlaybackRepeatMode get repeatMode => _repeatMode;
  double get volume => _volume;
  bool get canCrossfadeNext => _queueIndex >= 0 && _queueIndex < _queue.length - 1;
  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeDurationMs => _crossfadeDurationMs;
  String get crossfadeFadeType => _crossfadeFadeType;
  Stream<Duration?> get durationStream => audioPlayer.durationStream;

  Future<void> _loadPlaybackSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _shuffleEnabled = prefs.getBool(_shuffleEnabledKey) ?? false;
      final repeat = prefs.getString(_repeatModeKey) ?? 'off';
      _repeatMode = switch (repeat) {
        'all' => PlaybackRepeatMode.all,
        'one' => PlaybackRepeatMode.one,
        _ => PlaybackRepeatMode.off,
      };
      _crossfadeEnabled = prefs.getBool(_crossfadeEnabledKey) ?? false;
      _crossfadeDurationMs = (prefs.getInt(_crossfadeDurationKey) ?? 3000).clamp(500, 12000).toInt();
      _crossfadeFadeType = prefs.getString(_crossfadeFadeTypeKey) ?? 'linear';
      _applyEngineModes();
      notifyListeners();
    } catch (e) {
      debugPrint('Playback settings load failed: $e');
    }
  }

  void _applyEngineModes() {
    _engine.setShuffle(_shuffleEnabled);
    _engine.setRepeat(
      one: _repeatMode == PlaybackRepeatMode.one,
      all: _repeatMode == PlaybackRepeatMode.all,
    );
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    _engine.setShuffle(enabled);
    await _persistPlaybackModes();
    await _persistQueue();
    _syncQueueFromEngine();
    notifyListeners();
  }

  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _repeatMode = mode;
    _engine.setRepeat(one: mode == PlaybackRepeatMode.one, all: mode == PlaybackRepeatMode.all);
    await _persistPlaybackModes();
    notifyListeners();
  }

  Future<void> _persistPlaybackModes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_shuffleEnabledKey, _shuffleEnabled);
      await prefs.setString(_repeatModeKey, switch (_repeatMode) {
        PlaybackRepeatMode.all => 'all',
        PlaybackRepeatMode.one => 'one',
        PlaybackRepeatMode.off => 'off',
      });
    } catch (e) {
      debugPrint('Playback mode save failed: $e');
    }
  }

  Future<void> setCrossfadeEnabled(bool enabled) async {
    // Crossfade is intentionally not part of the first remastered engine.
    // Keep the UI preference so the later DSP/transition layer can reuse it.
    _crossfadeEnabled = enabled;
    await _persistCrossfadeSettings();
    notifyListeners();
  }

  Future<void> setCrossfadeDuration(int milliseconds) async {
    _crossfadeDurationMs = milliseconds.clamp(500, 12000).toInt();
    _crossfadeEnabled = true;
    await _persistCrossfadeSettings();
    notifyListeners();
  }

  Future<void> setCrossfadeFadeType(String value) async {
    if (!const ['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(value)) return;
    _crossfadeFadeType = value;
    await _persistCrossfadeSettings();
    notifyListeners();
  }

  Future<void> _persistCrossfadeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_crossfadeEnabledKey, _crossfadeEnabled);
      await prefs.setInt(_crossfadeDurationKey, _crossfadeDurationMs);
      await prefs.setString(_crossfadeFadeTypeKey, _crossfadeFadeType);
    } catch (e) {
      debugPrint('Crossfade settings save failed: $e');
    }
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin && event.type == AudioInterruptionType.pause) unawaited(pause());
        if (event.begin && event.type == AudioInterruptionType.duck) unawaited(_duckForInterruption());
        if (!event.begin && event.type == AudioInterruptionType.duck && isPlaying) unawaited(setVolume(_volume));
      });
      _noisySubscription = session.becomingNoisyEventStream.listen((_) {
        if (isPlaying) unawaited(pause());
      });
    } catch (e) {
      debugPrint('Audio session setup failed: $e');
    }
  }

  Future<void> _duckForInterruption() async {
    try {
      await _engine.setVolume(_volume * .35);
    } catch (_) {}
  }

  Future<void> _restoreQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_savedQueueIdsKey) ?? const <String>[];
      _resumePositionMs = prefs.getInt(_resumePositionKey) ?? 0;
      _resumeSongId = prefs.getString(_resumeSongIdKey);
      if (ids.isEmpty || currentSong != null) return;
      final savedIndex = prefs.getInt(_savedQueueIndexKey) ?? 0;
      final songs = await _database.getAllSongs();
      final byId = <String, Song>{for (final song in songs) song.id: song};
      final restored = ids.map((id) => byId[id]).whereType<Song>().toList();
      if (restored.isEmpty) return;
      _queue = restored;
      _queueIndex = savedIndex.clamp(0, restored.length - 1).toInt();
      currentSong = _queue[_queueIndex];
      currentDuration = currentSong!.duration;
      currentPosition = Duration.zero;
      _syncEngineQueueWithoutPlaying();
      notifyListeners();
    } catch (e) {
      debugPrint('Playback queue restore failed: $e');
    }
  }

  void _syncEngineQueueWithoutPlaying() {
    // The engine's public queue is intentionally replaced only by playback
    // commands. Keeping provider state here avoids starting audio on startup.
    _engine.setQueue(_queue, startIndex: _queueIndex, autoplay: false);
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isEmpty) {
        await prefs.remove(_savedQueueIdsKey);
        await prefs.remove(_savedQueueIndexKey);
      } else {
        await prefs.setStringList(_savedQueueIdsKey, _queue.map((song) => song.id).toList());
        await prefs.setInt(_savedQueueIndexKey, _queueIndex);
      }
    } catch (e) {
      debugPrint('Playback queue persistence failed: $e');
    }
  }

  void _syncQueueFromEngine() {
    _queue = _engine.queue.toList();
    _queueIndex = _engine.index;
  }

  Future<void> _handleEngineSongChanged(Song song) async {
    _syncQueueFromEngine();
    currentSong = song;
    currentDuration = song.duration;
    currentPosition = Duration.zero;
    isPlaying = false;
    await _finishHistoryEvent();
    await _startHistoryEvent(song);
    await _persistQueue();
    _publishServiceState();
    notifyListeners();
  }

  void _publishServiceState() {
    final handler = audioHandler;
    if (handler is AudioServiceHandler) {
      handler.publishPlayback(
        song: currentSong,
        playing: isPlaying,
        position: currentPosition,
        duration: currentDuration,
        speed: 1.0,
      );
    }
  }

  void _persistResumePosition({bool force = false}) {
    final song = currentSong;
    if (song == null || _activeHistoryEvent == null) return;
    final now = DateTime.now();
    if (!force && _lastResumePersist != null && now.difference(_lastResumePersist!) < const Duration(seconds: 3)) return;
    _lastResumePersist = now;
    final position = _activeHistoryPositionMs.clamp(0, currentDuration?.inMilliseconds ?? 0).toInt();
    unawaited(SharedPreferences.getInstance().then((prefs) async {
      await prefs.setInt(_resumePositionKey, position);
      await prefs.setString(_resumeSongIdKey, song.id);
    }).catchError((error) {
      debugPrint('Playback resume save failed: $error');
    }));
  }

  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0}) async {
    final ok = await _engine.playSong(song, queue: queue, startIndex: startIndex, autoplay: true);
    if (!ok) return false;
    _syncQueueFromEngine();
    _applyEngineModes();
    if (_resumeSongId == song.id && _resumePositionMs > 0 && currentSong?.id == song.id) {
      final safe = _resumePositionMs.clamp(0, currentDuration?.inMilliseconds ?? _resumePositionMs).toInt();
      await _engine.seek(Duration(milliseconds: safe));
      currentPosition = Duration(milliseconds: safe);
    }
    isPlaying = true;
    _publishServiceState();
    notifyListeners();
    return true;
  }

  Future<void> togglePlayPause() async {
    try {
      if (_engine.isPlaying) {
        await pause();
      } else {
        if (_engine.player.audioSource != null) {
          await _engine.play();
          isPlaying = true;
        } else if (currentSong != null) {
          final ok = await _engine.playSong(currentSong!, queue: _queue, startIndex: _queueIndex, autoplay: true);
          if (!ok) return;
          isPlaying = true;
        }
        _publishServiceState();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Playback toggle failed: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _engine.pause();
      isPlaying = false;
      _persistResumePosition(force: true);
      _publishServiceState();
      notifyListeners();
    } catch (e) {
      debugPrint('Playback pause failed: $e');
    }
  }

  Future<void> stop() async {
    await _finishHistoryEvent();
    await _engine.stop();
    isPlaying = false;
    currentPosition = Duration.zero;
    _publishServiceState();
    notifyListeners();
  }

  Future<void> nextSong() async {
    final ok = await _engine.next();
    if (!ok) return;
    _syncQueueFromEngine();
    currentSong = _engine.currentSong;
    _applyEngineModes();
    isPlaying = true;
    await _persistQueue();
    _publishServiceState();
    notifyListeners();
  }

  Future<void> previousSong() async {
    final ok = await _engine.previous();
    if (!ok) return;
    _syncQueueFromEngine();
    currentSong = _engine.currentSong;
    currentDuration = currentSong?.duration;
    currentPosition = _engine.player.position;
    isPlaying = _engine.isPlaying;
    await _persistQueue();
    _publishServiceState();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    try {
      await _engine.seek(position);
      currentPosition = _engine.player.position;
      if (_activeHistoryEvent != null) _activeHistoryPositionMs = currentPosition.inMilliseconds;
      _persistResumePosition(force: true);
      _publishServiceState();
      notifyListeners();
    } catch (e) {
      debugPrint('Seek failed: $e');
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    await _engine.setVolume(_volume);
    notifyListeners();
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    final ok = await _engine.setQueue(songs, startIndex: startIndex, autoplay: true);
    if (!ok) return;
    _syncQueueFromEngine();
    currentSong = _engine.currentSong;
    currentDuration = currentSong?.duration;
    currentPosition = Duration.zero;
    isPlaying = true;
    await _persistQueue();
    _publishServiceState();
    notifyListeners();
  }

  Future<bool> enqueueSongs(List<Song> songs) async {
    var changed = false;
    for (final song in songs) {
      changed = await _engine.addToQueue(song) || changed;
    }
    if (!changed) return false;
    _syncQueueFromEngine();
    await _persistQueue();
    notifyListeners();
    return true;
  }

  Future<bool> addToQueue(Song song) => enqueueSongs([song]);

  Future<bool> playNext(Song song) async {
    final changed = await _engine.playNext(song);
    if (!changed) return false;
    _syncQueueFromEngine();
    await _persistQueue();
    notifyListeners();
    return true;
  }

  Future<bool> removeFromQueue(int index) async {
    final changed = await _engine.removeFromQueue(index);
    if (!changed) return false;
    _syncQueueFromEngine();
    await _persistQueue();
    notifyListeners();
    return true;
  }

  Future<bool> reorderQueue(int oldIndex, int newIndex) async {
    final changed = await _engine.reorderQueue(oldIndex, newIndex);
    if (!changed) return false;
    _syncQueueFromEngine();
    await _persistQueue();
    notifyListeners();
    return true;
  }

  void clearUpcomingQueue() {
    _engine.clearUpcoming();
    _syncQueueFromEngine();
    unawaited(_persistQueue());
    notifyListeners();
  }

  Future<bool> performTrueCrossfade({required int milliseconds, String fadeType = 'linear'}) async {
    // First engine milestone deliberately uses deterministic track switching.
    // The true two-deck DSP transition will be added only after the base engine
    // passes playback/queue/repeat/shuffle testing.
    if (!canCrossfadeNext) return false;
    await nextSong();
    return true;
  }

  Future<void> _startHistoryEvent(Song song) async {
    await _queueHistoryOperation(() async {
      if (_activeHistoryEvent?.songId == song.id) return;
      final event = ListeningEvent(
        id: '${DateTime.now().microsecondsSinceEpoch}_${song.id}',
        songId: song.id,
        previousSongId: _queueIndex > 0 ? _queue[_queueIndex - 1].id : null,
        startedAt: DateTime.now(),
        durationPlayedMs: currentPosition.inMilliseconds,
        songDurationMs: song.duration.inMilliseconds,
        completionRatio: 0,
        completed: false,
        skipped: false,
      );
      _activeHistoryEvent = event;
      _activeHistoryPositionMs = currentPosition.inMilliseconds;
      _resumePositionMs = currentPosition.inMilliseconds;
      _resumeSongId = song.id;
      try {
        await _database.insertListeningEvent(event);
        await _database.updateSongPlayCount(song.id);
      } catch (e) {
        debugPrint('Listening history start failed: $e');
      }
    });
  }

  Future<void> _finishHistoryEvent({bool completed = false}) async {
    await _queueHistoryOperation(() async {
      final event = _activeHistoryEvent;
      if (event == null) return;
      final total = event.songDurationMs > 0 ? event.songDurationMs : (currentDuration?.inMilliseconds ?? 0);
      final position = _activeHistoryPositionMs.clamp(0, total > 0 ? total : 1).toInt();
      final ratio = total <= 0 ? 0.0 : (position / total).clamp(0.0, 1.0).toDouble();
      final wasCompleted = completed || ratio >= .90;
      final updated = ListeningEvent(
        id: event.id,
        songId: event.songId,
        previousSongId: event.previousSongId,
        startedAt: event.startedAt,
        endedAt: DateTime.now(),
        durationPlayedMs: position,
        songDurationMs: total,
        completionRatio: ratio,
        completed: wasCompleted,
        skipped: !wasCompleted && position > 0,
        skipPositionMs: !wasCompleted && position > 0 ? position : null,
      );
      _activeHistoryEvent = null;
      _activeHistoryPositionMs = 0;
      if (wasCompleted) {
        _resumePositionMs = 0;
        _resumeSongId = null;
        unawaited(SharedPreferences.getInstance().then((prefs) async {
          await prefs.remove(_resumePositionKey);
          await prefs.remove(_resumeSongIdKey);
        }).catchError((error) {
          debugPrint('Playback resume clear failed: $error');
        }));
      } else {
        _persistResumePosition(force: true);
      }
      try {
        await _database.updateListeningEvent(updated);
      } catch (e) {
        debugPrint('Listening history finish failed: $e');
      }
    });
  }

  Future<void> _queueHistoryOperation(Future<void> Function() operation) {
    final next = _historySerial.then((_) => operation());
    _historySerial = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  @override
  void dispose() {
    _interruptionSubscription?.cancel();
    _noisySubscription?.cancel();
    unawaited(_engine.dispose());
    super.dispose();
  }
}
