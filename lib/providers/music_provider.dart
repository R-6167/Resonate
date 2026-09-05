import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/listening_event.dart';
import '../services/audio_service_handler.dart';
import '../services/database_helper.dart';

class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;
  final DatabaseHelper _database = DatabaseHelper();
  late final AudioPlayer _playerA;
  late final AudioPlayer _playerB;
  late final AndroidEqualizer _equalizerA;
  late final AndroidEqualizer _equalizerB;
  late final AndroidLoudnessEnhancer _loudnessA;
  late final AndroidLoudnessEnhancer _loudnessB;
  bool _activeIsA = true;
  AudioPlayer get audioPlayer => _activeIsA ? _playerA : _playerB;
  AudioPlayer get inactivePlayer => _activeIsA ? _playerB : _playerA;
  AndroidEqualizer get equalizer => _activeIsA ? _equalizerA : _equalizerB;
  AndroidLoudnessEnhancer get loudnessEnhancer => _activeIsA ? _loudnessA : _loudnessB;
  AndroidEqualizer get inactiveEqualizer => _activeIsA ? _equalizerB : _equalizerA;
  AndroidLoudnessEnhancer get inactiveLoudnessEnhancer => _activeIsA ? _loudnessB : _loudnessA;

  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration? currentDuration;
  double _volume = 1.0;
  List<Song> _queue = <Song>[];
  int _queueIndex = 0;
  bool _crossfadeInProgress = false;
  bool _completionAdvanceInProgress = false;
  bool _queueRestoreInProgress = false;
  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 3000;
  String _crossfadeFadeType = 'linear';
  bool _automaticCrossfadeInFlight = false;
  int _resumePositionMs = 0;
  String? _resumeSongId;
  DateTime? _lastResumePersist;
  Future<void> _playOperation = Future<void>.value();
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;

  ListeningEvent? _activeHistoryEvent;
  int _activeHistoryPositionMs = 0;
  Future<void> _historySerial = Future<void>.value();

  double get volume => _volume;
  List<Song> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  List<Song> get upcomingQueue => List.unmodifiable(_queue.skip(_queueIndex + 1));
  bool get canCrossfadeNext => _queueIndex >= 0 && _queueIndex < _queue.length - 1 && !_crossfadeInProgress;
  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeDurationMs => _crossfadeDurationMs;
  String get crossfadeFadeType => _crossfadeFadeType;

  static const _savedQueueIdsKey = 'playback_queue_song_ids';
  static const _savedQueueIndexKey = 'playback_queue_index';
  static const _crossfadeEnabledKey = 'crossfade_enabled';
  static const _crossfadeDurationKey = 'crossfade_duration';
  static const _crossfadeFadeTypeKey = 'crossfade_fade_type';
  static const _resumePositionKey = 'playback_resume_position_ms';
  static const _resumeSongIdKey = 'playback_resume_song_id';

  MusicProvider({this.audioHandler}) {
    _equalizerA = AndroidEqualizer();
    _equalizerB = AndroidEqualizer();
    _loudnessA = AndroidLoudnessEnhancer();
    _loudnessB = AndroidLoudnessEnhancer();
    _playerA = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerA, _loudnessA]));
    _playerB = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB, _loudnessB]));
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
    _bindActivePlayerStreams();
    unawaited(_configureAudioSession());
    unawaited(_loadPlaybackSettings());
    unawaited(_restoreQueue());
  }

  Future<void> _loadPlaybackSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _crossfadeEnabled = prefs.getBool(_crossfadeEnabledKey) ?? false;
      _crossfadeDurationMs = ((prefs.getDouble(_crossfadeDurationKey) ?? 3000).round().clamp(500, 12000)).toInt();
      _crossfadeFadeType = prefs.getString(_crossfadeFadeTypeKey) ?? 'linear';
      _resumePositionMs = prefs.getInt(_resumePositionKey) ?? 0;
      _resumeSongId = prefs.getString(_resumeSongIdKey);
      if (!const ['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(_crossfadeFadeType)) _crossfadeFadeType = 'linear';
      notifyListeners();
    } catch (e) {
      debugPrint('Playback settings load failed: $e');
    }
  }

  Future<void> setCrossfadeEnabled(bool enabled) async {
    _crossfadeEnabled = enabled;
    if (enabled && _crossfadeDurationMs <= 0) _crossfadeDurationMs = 3000;
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
      await prefs.setDouble(_crossfadeDurationKey, _crossfadeDurationMs.toDouble());
      await prefs.setString(_crossfadeFadeTypeKey, _crossfadeFadeType);
    } catch (e) {
      debugPrint('Playback crossfade save failed: $e');
    }
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin && (event.type == AudioInterruptionType.pause || event.type == AudioInterruptionType.duck)) unawaited(pause());
      });
      _noisySubscription = session.becomingNoisyEventStream.listen((_) { if (isPlaying) unawaited(pause()); });
    } catch (e) {
      debugPrint('Audio session setup failed: $e');
    }
  }

  Future<void> _restoreQueue() async {
    if (_queueRestoreInProgress) return;
    _queueRestoreInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_savedQueueIdsKey) ?? const <String>[];
      _resumePositionMs = prefs.getInt(_resumePositionKey) ?? _resumePositionMs;
      _resumeSongId = prefs.getString(_resumeSongIdKey) ?? _resumeSongId;
      if (ids.isEmpty || currentSong != null || _queue.isNotEmpty) return;
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
      notifyListeners();
    } catch (e) {
      debugPrint('Playback queue restore failed: $e');
    } finally {
      _queueRestoreInProgress = false;
    }
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

  void _publishServiceState() {
    final handler = audioHandler;
    if (handler is AudioServiceHandler) {
      handler.publishPlayback(song: currentSong, playing: isPlaying, position: currentPosition, duration: currentDuration, speed: 1.0);
    }
  }

  void _bindActivePlayerStreams() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _volumeSubscription?.cancel();
    final player = audioPlayer;
    _playerStateSubscription = player.playerStateStream.listen((state) {
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (isPlaying != playing) {
        isPlaying = playing;
        notifyListeners();
        _publishServiceState();
      }
      if (state.processingState == ProcessingState.completed) {
        currentPosition = currentDuration ?? currentPosition;
        isPlaying = false;
        notifyListeners();
        _publishServiceState();
        if (!_completionAdvanceInProgress && !_crossfadeInProgress && _queueIndex < _queue.length - 1) {
          unawaited(_advanceAfterCompletion());
        }
      }
    });
    _positionSubscription = player.positionStream.listen((position) {
      if (currentPosition != position) {
        currentPosition = position;
        if (_activeHistoryEvent != null) {
          _activeHistoryPositionMs = position.inMilliseconds;
          _persistResumePosition();
        }
        notifyListeners();
        _publishServiceState();
      }
      _maybeStartAutomaticCrossfade(position);
    });
    _durationSubscription = player.durationStream.listen((duration) {
      if (duration != null && currentDuration != duration) {
        currentDuration = duration;
        notifyListeners();
        _publishServiceState();
      }
    });
    _volumeSubscription = player.volumeStream.listen((value) {
      if (_volume != value) {
        _volume = value;
        notifyListeners();
      }
    });
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

  void _maybeStartAutomaticCrossfade(Duration position) {
    if (!_crossfadeEnabled || _automaticCrossfadeInFlight || !canCrossfadeNext || !audioPlayer.playing) return;
    final duration = audioPlayer.duration ?? currentDuration;
    if (duration == null || duration <= Duration.zero) return;
    final remaining = duration - position;
    if (remaining <= Duration.zero || remaining > Duration(milliseconds: _crossfadeDurationMs)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());
  }

  Future<void> _runAutomaticCrossfade() async {
    try {
      await performTrueCrossfade(milliseconds: _crossfadeDurationMs, fadeType: _crossfadeFadeType);
    } finally {
      _automaticCrossfadeInFlight = false;
    }
  }

  Future<void> _advanceAfterCompletion() async {
    if (_completionAdvanceInProgress) return;
    _completionAdvanceInProgress = true;
    try {
      await _finishHistoryEvent(completed: true);
      await nextSong();
    } finally {
      _completionAdvanceInProgress = false;
    }
  }

  Uri _audioUri(String value) {
    final path = value.trim();
    if (path.startsWith('content://') || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('file://')) return Uri.parse(path);
    return Uri.file(path);
  }

  Future<void> _stopBoth() async {
    try { await _playerA.stop(); } catch (_) {}
    try { await _playerB.stop(); } catch (_) {}
    try { await _playerA.setLoopMode(LoopMode.off); } catch (_) {}
    try { await _playerB.setLoopMode(LoopMode.off); } catch (_) {}
    try { await _playerA.setVolume(_volume); } catch (_) {}
    try { await _playerB.setVolume(_volume); } catch (_) {}
  }

  Future<void> _enableEffects(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud) async {
    try { await eq.setEnabled(true); } catch (e) { debugPrint('Equalizer unavailable: $e'); }
    try { await loud.setEnabled(true); } catch (e) { debugPrint('Loudness enhancer unavailable: $e'); }
  }

  Future<T> _serializePlayback<T>(Future<T> Function() operation) {
    final next = _playOperation.then((_) => operation());
    _playOperation = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0}) {
    return _serializePlayback(() => _playSongInternal(song, queue: queue, startIndex: startIndex));
  }

  Future<bool> _playSongInternal(Song song, {List<Song>? queue, int startIndex = 0, bool resume = false}) async {
    if (song.filePath.trim().isEmpty) return false;
    try {
      _crossfadeInProgress = false;
      await _finishHistoryEvent();
      await _stopBoth();
      _activeIsA = true;
      final requested = queue != null && queue.isNotEmpty ? List<Song>.from(queue) : <Song>[song];
      final normalized = requested.where((s) => s.filePath.trim().isNotEmpty).toList();
      if (normalized.isEmpty) return false;
      final selectedIndex = normalized.indexWhere((s) => s.id == song.id);
      _queue = normalized;
      _queueIndex = selectedIndex >= 0 ? selectedIndex : startIndex.clamp(0, normalized.length - 1).toInt();
      currentSong = _queue[_queueIndex];
      currentDuration = currentSong!.duration;
      currentPosition = Duration.zero;
      isPlaying = false;
      await _persistQueue();
      _bindActivePlayerStreams();
      notifyListeners();
      await audioPlayer.setLoopMode(LoopMode.off);
      await audioPlayer.setAudioSource(AudioSource.uri(_audioUri(currentSong!.filePath), tag: currentSong));
      if (resume && _resumeSongId == currentSong!.id && _resumePositionMs > 0) {
        final durationMs = currentDuration?.inMilliseconds ?? _resumePositionMs;
        final safeResume = _resumePositionMs.clamp(0, durationMs).toInt();
        await audioPlayer.seek(Duration(milliseconds: safeResume));
        currentPosition = Duration(milliseconds: safeResume);
      }
      await _enableEffects(audioPlayer, equalizer, loudnessEnhancer);
      await audioPlayer.setVolume(_volume);
      await audioPlayer.play();
      isPlaying = true;
      await _startHistoryEvent(currentSong!);
      _publishServiceState();
      notifyListeners();
      return true;
    } catch (e, stack) {
      isPlaying = false;
      debugPrint('Error playing song: $e');
      debugPrint('$stack');
      _publishServiceState();
      notifyListeners();
      return false;
    }
  }

  Future<void> _startHistoryEvent(Song song) async {
    await _queueHistoryOperation(() async {
      if (_activeHistoryEvent?.songId == song.id) return;
      await _finishHistoryEvent();
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

  Future<bool> enqueueSongs(List<Song> songs) async {
    final additions = songs.where((s) => s.filePath.trim().isNotEmpty && !_queue.any((q) => q.id == s.id)).toList();
    if (additions.isEmpty) return false;
    _queue.addAll(additions);
    await _persistQueue();
    notifyListeners();
    return true;
  }

  Future<bool> addToQueue(Song song) => enqueueSongs([song]);

  Future<bool> playNext(Song song) async {
    if (song.filePath.trim().isEmpty || currentSong?.id == song.id || _queue.any((q) => q.id == song.id)) return false;
    final insertAt = (_queueIndex + 1).clamp(0, _queue.length).toInt();
    _queue.insert(insertAt, song);
    await _persistQueue();
    notifyListeners();
    return true;
  }

  Future<bool> removeFromQueue(int index) async {
    if (index <= _queueIndex || index >= _queue.length) return false;
    _queue.removeAt(index);
    await _persistQueue();
    notifyListeners();
    return true;
  }

  Future<bool> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex <= _queueIndex || oldIndex >= _queue.length) return false;
    if (newIndex > oldIndex) newIndex--;
    newIndex = newIndex.clamp(_queueIndex + 1, _queue.length - 1).toInt();
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    await _persistQueue();
    notifyListeners();
    return true;
  }

  void clearUpcomingQueue() {
    if (_queueIndex >= _queue.length - 1) return;
    _queue = [..._queue.take(_queueIndex + 1)];
    unawaited(_persistQueue());
    notifyListeners();
  }

  Future<void> _loadSingle(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud, Song song, {bool start = true}) async {
    await player.setLoopMode(LoopMode.off);
    await player.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song));
    await _enableEffects(player, eq, loud);
    await player.setVolume(start ? _volume : 0.0);
    if (start) await player.play();
  }

  Future<bool> performTrueCrossfade({required int milliseconds, String fadeType = 'linear'}) {
    return _serializePlayback(() => _performTrueCrossfade(milliseconds: milliseconds, fadeType: fadeType));
  }

  Future<bool> _performTrueCrossfade({required int milliseconds, String fadeType = 'linear'}) async {
    if (!canCrossfadeNext || currentSong == null || !audioPlayer.playing) return false;
    final nextIndex = _queueIndex + 1;
    final nextSong = _queue[nextIndex];
    if (nextSong.filePath.trim().isEmpty) return false;
    _crossfadeInProgress = true;
    final outgoing = audioPlayer;
    final incoming = inactivePlayer;
    final incomingEq = inactiveEqualizer;
    final incomingLoud = inactiveLoudnessEnhancer;
    final master = _volume;
    try {
      await outgoing.setLoopMode(LoopMode.off);
      await incoming.stop();
      await _loadSingle(incoming, incomingEq, incomingLoud, nextSong, start: false);
      await incoming.setVolume(0.0);
      await incoming.play();
      final total = milliseconds.clamp(500, 12000).toInt();
      final steps = (total / 50).round().clamp(10, 240).toInt();
      for (var i = 1; i <= steps; i++) {
        final linear = i / steps;
        final t = switch (fadeType) {
          'ease_in' => linear * linear,
          'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)),
          'ease_in_out' => linear < 0.5 ? 2.0 * linear * linear : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0,
          _ => linear,
        };
        await outgoing.setVolume(master * (1.0 - t));
        await incoming.setVolume(master * t);
        await Future<void>.delayed(Duration(milliseconds: (total / steps).round()));
      }
      await outgoing.pause();
      await outgoing.setVolume(master);
      await incoming.setLoopMode(LoopMode.off);
      await incoming.setVolume(master);
      _activeIsA = !_activeIsA;
      _queueIndex = nextIndex;
      currentSong = nextSong;
      currentDuration = nextSong.duration;
      currentPosition = incoming.position;
      isPlaying = incoming.playing;
      await _finishHistoryEvent();
      await _persistQueue();
      _bindActivePlayerStreams();
      await _startHistoryEvent(nextSong);
      _publishServiceState();
      notifyListeners();
      await outgoing.stop();
      return true;
    } catch (e, stack) {
      debugPrint('True crossfade failed: $e');
      try { await incoming.stop(); } catch (_) {}
      try { await outgoing.setVolume(master); } catch (_) {}
      try {
        await outgoing.stop();
        await _playSongInternal(nextSong, queue: _queue, startIndex: nextIndex);
        return true;
      } catch (fallbackError) {
        debugPrint('Crossfade fallback failed: $fallbackError');
        return false;
      }
    } finally {
      _crossfadeInProgress = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    return _serializePlayback(() async {
      try {
        if (audioPlayer.playing) {
          await audioPlayer.pause();
          _publishServiceState();
          return;
        }
        if (audioPlayer.audioSource != null) {
          await audioPlayer.play();
          isPlaying = true;
          _publishServiceState();
          notifyListeners();
        } else if (currentSong != null) {
          await _playSongInternal(currentSong!, queue: _queue.isEmpty ? null : _queue, startIndex: _queueIndex, resume: true);
        }
      } catch (e) {
        debugPrint('Playback toggle failed: $e');
      }
    });
  }

  Future<void> pause() async {
    return _serializePlayback(() async {
      try {
        await audioPlayer.pause();
        isPlaying = false;
        _persistResumePosition(force: true);
        _publishServiceState();
        notifyListeners();
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    return _serializePlayback(() async {
      await _finishHistoryEvent();
      await _stopBoth();
      isPlaying = false;
      currentPosition = Duration.zero;
      _publishServiceState();
      notifyListeners();
    });
  }

  Future<void> nextSong() {
    return _serializePlayback(() async {
      if (_queueIndex < 0 || _queueIndex >= _queue.length - 1) return;
      final nextIndex = _queueIndex + 1;
      if (_crossfadeEnabled && canCrossfadeNext && audioPlayer.playing) {
        final didCrossfade = await _performTrueCrossfade(milliseconds: _crossfadeDurationMs, fadeType: _crossfadeFadeType);
        if (didCrossfade) return;
      }
      await _playSongInternal(_queue[nextIndex], queue: _queue, startIndex: nextIndex);
    });
  }

  Future<void> previousSong() {
    return _serializePlayback(() async {
      if (_queueIndex > 0) {
        final previousIndex = _queueIndex - 1;
        await _playSongInternal(_queue[previousIndex], queue: _queue, startIndex: previousIndex);
      } else {
        await audioPlayer.seek(Duration.zero);
        currentPosition = Duration.zero;
        if (_activeHistoryEvent != null) _activeHistoryPositionMs = 0;
        _persistResumePosition(force: true);
        notifyListeners();
      }
    });
  }

  Future<void> seek(Duration position) async {
    return _serializePlayback(() async {
      try {
        final duration = audioPlayer.duration ?? currentDuration ?? Duration.zero;
        final safe = Duration(milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds).toInt());
        await audioPlayer.seek(safe);
        currentPosition = safe;
        if (_activeHistoryEvent != null) _activeHistoryPositionMs = safe.inMilliseconds;
        _persistResumePosition(force: true);
        _publishServiceState();
        notifyListeners();
      } catch (_) {}
    });
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    try {
      await audioPlayer.setVolume(_volume);
      if (!inactivePlayer.playing) await inactivePlayer.setVolume(_volume);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) {
      await _finishHistoryEvent();
      _queue = <Song>[];
      _queueIndex = 0;
      await _persistQueue();
      notifyListeners();
      return;
    }
    final index = startIndex.clamp(0, songs.length - 1).toInt();
    await playSong(songs[index], queue: songs, startIndex: index);
  }

  Stream<Duration?> get durationStream => audioPlayer.durationStream;

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _volumeSubscription?.cancel();
    _interruptionSubscription?.cancel();
    _noisySubscription?.cancel();
    _playerA.dispose();
    _playerB.dispose();
    super.dispose();
  }
}
