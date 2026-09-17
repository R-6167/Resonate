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

/// Resonate playback core — public contract (Phase 0)
///
/// UI and Intelligence should only drive playback through:
///   playSong / playQueueIndex  — start a song (set queue + index + play)
///   nextSong / previousSong    — transport
///   togglePlayPause / pause / seek / stop
///   enqueueSongs / playNext / removeFromQueue / reorderQueue
///
/// Internal only:
///   onTrackEnded (completion)  — advance / repeat / stop
///
/// Intelligence must not set engines, intent tokens, or isPlaying directly.
/// Engine A is the primary player; Engine B is for crossfade / Autopilot preload.

enum PlaybackRepeatMode { off, all, one }

class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;
  final DatabaseHelper _database = DatabaseHelper();
  final PlaybackAuthority _authority = PlaybackAuthority.instance;
  final PlaybackIntentGate _playbackIntentGate = PlaybackIntentGate();
  final PlaybackCoordinator _playbackCoordinator = PlaybackCoordinator();
  late final AudioEffectsController _audioEffectsController;
  final LibraryVisibilityStore _visibility = LibraryVisibilityStore.instance;
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
  bool _shuffleEnabled = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;
  bool _crossfadeInProgress = false;
  bool _completionAdvanceInProgress = false;
  bool _completionObservedDuringCrossfade = false;
  bool _queueRestoreInProgress = false;
  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 3000;
  String _crossfadeFadeType = 'linear';
  bool _automaticCrossfadeInFlight = false;
  String? _preloadedNextSongId;
  bool _crossfadePreloadInFlight = false;
  bool _userWantsPlaying = false;
  bool _loadingSource = false;
  DateTime? _lastPlayKickAt;
  int _resumePositionMs = 0;
  String? _resumeSongId;
  DateTime? _lastResumePersist;
  Timer? _systemVolumePollTimer;
  Timer? _endOfTrackWatchdog;
  String? _lastCompletionSongId;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;

  ListeningEvent? _activeHistoryEvent;
  int _activeHistoryPositionMs = 0;
  Future<void> _historySerial = Future<void>.value();
  bool _historyOperationActive = false;

  double get volume => _volume;
  List<Song> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  List<Song> get upcomingQueue => List.unmodifiable(_queue.skip(_queueIndex + 1));
  bool get shuffleEnabled => _shuffleEnabled;
  PlaybackRepeatMode get repeatMode => _repeatMode;
  bool get canCrossfadeNext => _queueIndex >= 0 && _queueIndex < _queue.length - 1 && !_crossfadeInProgress;
  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeDurationMs => _crossfadeDurationMs;
  String get crossfadeFadeType => _crossfadeFadeType;
  String get activeEngineLabel => _authority.engineLabel(this);
  bool get transitionInProgress => _crossfadeInProgress || _automaticCrossfadeInFlight;

  /// Phase 2: normal listening is always Engine A. Engine B is only for an
  /// in-progress crossfade (or a track that was handed off via crossfade).
  bool get isEngineA => _activeIsA;

  /// Switch active engine to A and rebind streams if we were on B.
  /// Safe to call at the start of any non-crossfade play path.
  void _ensureEngineA({String reason = 'default'}) {
    if (_activeIsA) return;
    _activeIsA = true;
    _bindActivePlayerStreams();
    unawaited(ResonateDiagnostics.record('engine_policy', {
      'action': 'promote_a',
      'reason': reason,
      'songId': currentSong?.id,
      'queueIndex': _queueIndex,
    }));
    // Quiet B so it cannot steal focus after a crossfade.
    unawaited(() async {
      try {
        await _playerB.pause();
      } catch (_) {}
      try {
        await _playerB.setVolume(0.0);
      } catch (_) {}
    }());
  }


  static const _savedQueueIdsKey = 'playback_queue_song_ids';
  static const _savedQueueIndexKey = 'playback_queue_index';
  static const _shuffleEnabledKey = 'playback_shuffle_enabled';
  static const _repeatModeKey = 'playback_repeat_mode';
  static const _crossfadeEnabledKey = 'crossfade_enabled';
  static const _crossfadeDurationKey = 'crossfade_duration';
  static const _crossfadeFadeTypeKey = 'crossfade_fade_type';
  static const _resumePositionKey = 'playback_resume_position_ms';
  static const _resumeSongIdKey = 'playback_resume_song_id';
  static const MethodChannel _systemVolumeChannel = MethodChannel('com.example.resonate/media_store');

  MusicProvider({this.audioHandler}) {
    _equalizerA = AndroidEqualizer();
    _equalizerB = AndroidEqualizer();
    _loudnessA = AndroidLoudnessEnhancer();
    _loudnessB = AndroidLoudnessEnhancer();
    _audioEffectsController = AudioEffectsController(equalizerA: _equalizerA, equalizerB: _equalizerB, loudnessA: _loudnessA, loudnessB: _loudnessB);
    _playerA = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerA, _loudnessA]));
    _playerB = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB, _loudnessB]));
    if (audioHandler is AudioServiceHandler) {
      (audioHandler! as AudioServiceHandler).bindPlaybackController(
        // CRITICAL: onPlay must never toggle. If isPlaying was optimistic-true
        // while native was still paused, toggle would take the pause branch and
        // leave the track loaded but silent (library tap / auto-next bug).
        onPlay: () => resumePlayback(source: 'audio_service'),
        onPause: () => pause(source: 'audio_service'),
        onStop: () => stop(source: 'audio_service'),
        onSeek: (position) => seek(position, source: 'audio_service'),
        onNext: () => nextSong(source: 'audio_service'),
        onPrevious: () => previousSong(source: 'audio_service'),
      );
    }
    _bindActivePlayerStreams();
    unawaited(_configureAudioSession());
    unawaited(_loadPlaybackSettings());
    _systemVolumePollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(_syncSystemVolume()));
    unawaited(_restoreQueue());
  }

  Future<void> _loadPlaybackSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _shuffleEnabled = prefs.getBool(_shuffleEnabledKey) ?? false;
      final repeat = prefs.getString(_repeatModeKey) ?? 'off';
      _repeatMode = switch (repeat) { 'all' => PlaybackRepeatMode.all, 'one' => PlaybackRepeatMode.one, _ => PlaybackRepeatMode.off };
      _crossfadeEnabled = prefs.getBool(_crossfadeEnabledKey) ?? false;
      _crossfadeDurationMs = ((prefs.getDouble(_crossfadeDurationKey) ?? 3000).round().clamp(500, 12000)).toInt();
      _crossfadeFadeType = prefs.getString(_crossfadeFadeTypeKey) ?? 'linear';
      _resumePositionMs = prefs.getInt(_resumePositionKey) ?? 0;
      _resumeSongId = prefs.getString(_resumeSongIdKey);
      await _syncSystemVolume();
      await syncSavedAudioEffects();
      if (!const ['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(_crossfadeFadeType)) _crossfadeFadeType = 'linear';
      notifyListeners();
    } catch (e) { debugPrint('Playback settings load failed: $e'); }
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    if (enabled && _queue.length > 1 && _queueIndex < _queue.length - 1) {
      final current = _queue[_queueIndex];
      final upcoming = _queue.sublist(_queueIndex + 1)..shuffle(Random());
      _queue = [..._queue.take(_queueIndex + 1), ...upcoming];
      _queueIndex = _queue.indexWhere((song) => song.id == current.id);
    }
    await _persistPlaybackModes(); await _persistQueue(); notifyListeners();
  }

  Future<void> setRepeatMode(PlaybackRepeatMode mode) async { _repeatMode = mode; await _persistPlaybackModes(); notifyListeners(); }

  Future<void> _persistPlaybackModes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_shuffleEnabledKey, _shuffleEnabled);
      await prefs.setString(_repeatModeKey, switch (_repeatMode) { PlaybackRepeatMode.all => 'all', PlaybackRepeatMode.one => 'one', PlaybackRepeatMode.off => 'off' });
    } catch (e) { debugPrint('Playback mode save failed: $e'); }
  }

  Future<void> setCrossfadeEnabled(bool enabled) async { _crossfadeEnabled = enabled; if (enabled && _crossfadeDurationMs <= 0) _crossfadeDurationMs = 3000; await _persistCrossfadeSettings(); notifyListeners(); }
  Future<void> setCrossfadeDuration(int milliseconds) async { _crossfadeDurationMs = milliseconds.clamp(500, 12000).toInt(); _crossfadeEnabled = true; await _persistCrossfadeSettings(); notifyListeners(); }
  Future<void> setCrossfadeFadeType(String value) async { if (!const ['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(value)) return; _crossfadeFadeType = value; await _persistCrossfadeSettings(); notifyListeners(); }

  Future<void> _persistCrossfadeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_crossfadeEnabledKey, _crossfadeEnabled);
      await prefs.setDouble(_crossfadeDurationKey, _crossfadeDurationMs.toDouble());
      await prefs.setString(_crossfadeFadeTypeKey, _crossfadeFadeType);
    } catch (e) { debugPrint('Playback crossfade save failed: $e'); }
  }

  Future<void> syncSavedAudioEffects() async {
    try { await _audioEffectsController.syncAll(); } catch (e) { debugPrint('Saved audio effects sync failed: $e'); }
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin && event.type == AudioInterruptionType.pause) unawaited(pause(source: 'system'));
        if (event.begin && event.type == AudioInterruptionType.duck) unawaited(_duckForInterruption());
        if (!event.begin && event.type == AudioInterruptionType.duck && isPlaying) unawaited(setVolume(_volume));
      });
      _noisySubscription = session.becomingNoisyEventStream.listen((_) { if (isPlaying) unawaited(pause(source: 'system')); });
    } catch (e) { debugPrint('Audio session setup failed: $e'); }
  }

  Future<void> _duckForInterruption() async { try { await audioPlayer.setVolume(.35); } catch (_) {} }

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
      await _visibility.load();
      final visibleSongs = _visibility.filter(songs, (song) => song.id);
      final byId = <String, Song>{for (final song in visibleSongs) song.id: song};
      final restored = ids.map((id) => byId[id]).whereType<Song>().toList();
      if (restored.isEmpty) return;
      _queue = restored; _queueIndex = savedIndex.clamp(0, restored.length - 1).toInt(); currentSong = _queue[_queueIndex]; currentDuration = currentSong!.duration; currentPosition = Duration.zero; notifyListeners();
    } catch (e) { debugPrint('Playback queue restore failed: $e'); } finally { _queueRestoreInProgress = false; }
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isEmpty) { await prefs.remove(_savedQueueIdsKey); await prefs.remove(_savedQueueIndexKey); }
      else { await prefs.setStringList(_savedQueueIdsKey, _queue.map((song) => song.id).toList()); await prefs.setInt(_savedQueueIndexKey, _queueIndex); }
    } catch (e) { debugPrint('Playback queue persistence failed: $e'); }
  }

  void _publishServiceState() { final handler = audioHandler; if (handler is AudioServiceHandler) handler.publishPlayback(song: currentSong, playing: isPlaying, position: currentPosition, duration: currentDuration, speed: 1.0, bufferedPosition: audioPlayer.bufferedPosition, playbackQueue: _queue, queueIndex: _queueIndex); }

  void _bindActivePlayerStreams() {
    _playerStateSubscription?.cancel(); _positionSubscription?.cancel(); _durationSubscription?.cancel(); _volumeSubscription?.cancel();
    final player = audioPlayer;
    _playerStateSubscription = player.playerStateStream.listen((state) {
      final completed = state.processingState == ProcessingState.completed;
      final loading = state.processingState == ProcessingState.loading ||
          state.processingState == ProcessingState.buffering;
      // Do not force isPlaying=false while loading/buffering after a user play request.
      // That was the main "loaded but needs resume" bug.
      if (completed) {
        // Do not force isPlaying=false here when auto-next is intended.
        // Clearing it races with _playSongInternal and causes "loaded but needs resume".
        // Advance / queue-exhaust paths own the final isPlaying value.
      } else if (state.playing) {
        if (!isPlaying) {
          isPlaying = true;
          _userWantsPlaying = true;
          notifyListeners();
          _publishServiceState();
        }
      } else if (!loading && !state.playing && !_userWantsPlaying) {
        if (isPlaying) {
          isPlaying = false;
          notifyListeners();
          _publishServiceState();
        }
      } else if (!loading &&
          !state.playing &&
          _userWantsPlaying &&
          !_loadingSource &&
          player.audioSource != null) {
        // Kick play when a source is loaded and we still want audio.
        // Shorter throttle so auto-next / library taps recover quickly if the
        // first play() after setAudioSource did not stick.
        final now = DateTime.now();
        final due = _lastPlayKickAt == null ||
            now.difference(_lastPlayKickAt!) > const Duration(milliseconds: 250);
        if (due) {
          _lastPlayKickAt = now;
          isPlaying = true;
          unawaited(() async {
            try {
              final session = await AudioSession.instance;
              await session.setActive(true);
            } catch (_) {}
            try {
              await player.seek(player.position);
            } catch (_) {}
            try {
              await player.play();
            } catch (_) {}
          }());
          notifyListeners();
          _publishServiceState();
        }
      }
      if (completed) {
        final completedSongId = currentSong?.id;
        // just_audio can replay completed while A/B listeners are rebound.
        // Advance only once per song to prevent competing source loads.
        if (completedSongId == null || completedSongId == _lastCompletionSongId) return;
        _lastCompletionSongId = completedSongId;
        currentPosition = currentDuration ?? currentPosition;
        // Stay "want playing" so the next track auto-starts (not resume).
        // Do NOT set isPlaying=false here — that raced with the advance play()
        // and left the new track loaded but paused.
        _userWantsPlaying = true;
        notifyListeners();
        _publishServiceState();
        final upcoming = _queueIndex < _queue.length - 1 || _repeatMode == PlaybackRepeatMode.all;
        unawaited(ResonateDiagnostics.record('completion_detected', {
          'songId': completedSongId,
          'queueIndex': _queueIndex,
          'queueLength': _queue.length,
          'upcomingCount': upcoming ? _queue.length - _queueIndex - 1 : 0,
          'repeatMode': _repeatMode.name,
          'crossfadeInProgress': _crossfadeInProgress,
          'automaticCrossfadeInFlight': _automaticCrossfadeInFlight,
        }));
        if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
          // Remember that the outgoing track finished while we were fading.
          // We will force an advance after the crossfade finishes (or fails).
          _completionObservedDuringCrossfade = true;
        } else if (!_completionAdvanceInProgress) {
          unawaited(onTrackEnded(completedSongId));
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
      _armEndOfTrackWatchdog();
    });
    _durationSubscription = player.durationStream.listen((duration) { if (duration != null && currentDuration != duration) { currentDuration = duration; notifyListeners(); _publishServiceState(); } });
    // App volume is sourced from Android STREAM_MUSIC. Do not mirror the player's
    // internal gain into _volume or it will overwrite the system-volume value.
  }

  void _persistResumePosition({bool force = false}) {
    final song = currentSong; if (song == null || _activeHistoryEvent == null) return;
    final now = DateTime.now(); if (!force && _lastResumePersist != null && now.difference(_lastResumePersist!) < const Duration(seconds: 3)) return;
    _lastResumePersist = now; final position = _activeHistoryPositionMs.clamp(0, currentDuration?.inMilliseconds ?? 0).toInt();
    unawaited(SharedPreferences.getInstance().then((prefs) async { await prefs.setInt(_resumePositionKey, position); await prefs.setString(_resumeSongIdKey, song.id); }).catchError((error) { debugPrint('Playback resume save failed: $error'); }));
  }

  void _maybeStartAutomaticCrossfade(Duration position) {
    if (!_crossfadeEnabled || !canCrossfadeNext || !audioPlayer.playing) return;
    final duration = audioPlayer.duration ?? currentDuration;
    if (duration == null || duration <= Duration.zero) return;
    final remaining = duration - position;
    if (remaining <= Duration.zero) return;

    // Phase 1: preload next on the inactive engine well before the fade window
    // so setAudioSource is not racing the end of the track.
    final preloadMs = (_crossfadeDurationMs + 8000).clamp(8000, 22000);
    if (remaining <= Duration(milliseconds: preloadMs) &&
        remaining > Duration(milliseconds: _crossfadeDurationMs + 400)) {
      unawaited(_preloadNextForCrossfade());
      return;
    }

    if (_automaticCrossfadeInFlight) return;
    if (remaining > Duration(milliseconds: _crossfadeDurationMs)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());
  }

  Future<void> _preloadNextForCrossfade() async {
    if (!_crossfadeEnabled || _crossfadePreloadInFlight || !canCrossfadeNext) return;
    if (_queueIndex < 0 || _queueIndex >= _queue.length - 1) return;
    final next = _queue[_queueIndex + 1];
    if (_preloadedNextSongId == next.id) return;
    _crossfadePreloadInFlight = true;
    try {
      final incoming = inactivePlayer;
      final incomingEq = inactiveEqualizer;
      final incomingLoud = inactiveLoudnessEnhancer;
      await incoming.setLoopMode(LoopMode.off);
      try {
        await incoming.stop();
      } catch (_) {}
      await incoming.setAudioSource(AudioSource.uri(_audioUri(next.filePath), tag: next));
      unawaited(_enableEffects(incoming, incomingEq, incomingLoud));
      await incoming.setVolume(0.0);
      try {
        incoming.play();
      } catch (_) {}
      // Brief wait so the decoder attaches without blocking the position stream long.
      for (var i = 0; i < 8 && !incoming.playing; i++) {
        await Future<void>.delayed(Duration(milliseconds: 40 + i * 20));
        if (i % 3 == 0) {
          try {
            incoming.play();
          } catch (_) {}
        }
      }
      _preloadedNextSongId = next.id;
      await ResonateDiagnostics.record('crossfade_preloaded', {
        'songId': next.id,
        'queueIndex': _queueIndex + 1,
        'playing': incoming.playing,
      });
    } catch (e) {
      _preloadedNextSongId = null;
      debugPrint('crossfade preload failed: $e');
      await ResonateDiagnostics.record('crossfade_preload_failed', {
        'error': e.toString(),
      });
    } finally {
      _crossfadePreloadInFlight = false;
    }
  }

  Future<void> _runAutomaticCrossfade() async {
    final generation = _authority.beginAutomatic('automatic_crossfade');
    final fromIndex = _queueIndex;
    final fromSongId = currentSong?.id;
    try {
      final timeout = Duration(milliseconds: (_crossfadeDurationMs + 10000).clamp(8000, 25000));
      final ok = await _performTrueCrossfade(
        milliseconds: _crossfadeDurationMs,
        fadeType: _crossfadeFadeType,
        generation: generation,
      ).timeout(timeout, onTimeout: () {
        debugPrint('automatic crossfade timed out');
        return false;
      });
      if (ok) return;
      // Watchdog or user may already have advanced — do not double-load the next URI
      // (causes MediaStore "Connection aborted" + static on this OEM).
      if (currentSong?.id != fromSongId || _queueIndex != fromIndex) {
        await ResonateDiagnostics.record('crossfade_fallback_skipped_already_advanced', {
          'fromSongId': fromSongId,
          'fromIndex': fromIndex,
          'nowSongId': currentSong?.id,
          'nowIndex': _queueIndex,
        });
        try {
          await inactivePlayer.stop();
        } catch (_) {}
        return;
      }
      await ResonateDiagnostics.record('crossfade_fallback_to_play', {
        'fromSongId': fromSongId,
        'queueIndex': fromIndex,
      });
      try {
        await inactivePlayer.stop();
      } catch (_) {}
      if (fromIndex < _queue.length - 1) {
        final next = _queue[fromIndex + 1];
        final token = _playbackIntentGate.issue();
        await _playSongInternal(next, queue: _queue, startIndex: fromIndex + 1, playbackIntentToken: token);
      }
    } catch (e) {
      debugPrint('automatic crossfade error: $e');
      if (currentSong?.id == fromSongId && _queueIndex == fromIndex && fromIndex < _queue.length - 1) {
        try {
          await inactivePlayer.stop();
        } catch (_) {}
        try {
          final next = _queue[fromIndex + 1];
          final token = _playbackIntentGate.issue();
          await _playSongInternal(next, queue: _queue, startIndex: fromIndex + 1, playbackIntentToken: token);
        } catch (_) {}
      }
    } finally {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
    }
  }

  /// Safety net: if the player sits at the end of a track without advancing,
  /// force a completion advance after a short grace period.
  void _armEndOfTrackWatchdog() {
    _endOfTrackWatchdog?.cancel();
    final duration = currentDuration;
    if (duration == null || duration <= Duration.zero) return;
    final remaining = duration - currentPosition;
    if (remaining > const Duration(seconds: 4)) return;

    // With crossfade on, give the dual-engine fade the full window before intervening.
    // The previous 1.2s grace fired mid-fade, raced Engine A load, and caused
    // "Connection aborted" + static on content:// URIs.
    final expectedSongId = currentSong?.id;
    final expectedIndex = _queueIndex;
    final graceMs = _crossfadeEnabled
        ? (_crossfadeDurationMs + 4500).clamp(5000, 20000)
        : 1200;

    _endOfTrackWatchdog = Timer(remaining + Duration(milliseconds: graceMs), () {
      if (currentSong == null || _completionAdvanceInProgress) return;
      // Already moved on (successful crossfade or manual next).
      if (currentSong?.id != expectedSongId || _queueIndex != expectedIndex) return;

      if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
        unawaited(ResonateDiagnostics.record('end_of_track_watchdog_crossfade_stuck', {
          'songId': currentSong?.id,
          'crossfadeInProgress': _crossfadeInProgress,
          'automaticCrossfadeInFlight': _automaticCrossfadeInFlight,
          'graceMs': graceMs,
        }));
        _crossfadeInProgress = false;
        _automaticCrossfadeInFlight = false;
        _completionObservedDuringCrossfade = false;
        // Silence B so a half-started fade cannot keep making static.
        unawaited(() async {
          try {
            await _playerB.stop();
          } catch (_) {}
          try {
            await _playerB.setVolume(0.0);
          } catch (_) {}
        }());
      }

      final atEnd = !isPlaying ||
          currentPosition >= duration - const Duration(milliseconds: 400) ||
          audioPlayer.processingState == ProcessingState.completed;
      final canAdvance = _queueIndex < _queue.length - 1 ||
          _repeatMode != PlaybackRepeatMode.off;
      if (atEnd && canAdvance) {
        unawaited(ResonateDiagnostics.record('end_of_track_watchdog_fired', {
          'songId': currentSong!.id,
          'queueIndex': _queueIndex,
          'isPlaying': isPlaying,
          'positionMs': currentPosition.inMilliseconds,
        }));
        unawaited(onTrackEnded(currentSong!.id));
      }
    });
  }

  /// After a crossfade finishes, ensure playback continues if the outgoing
  /// track reached completed while the fade was in progress.
  Future<void> _ensureContinueAfterCrossfade() async {
    if (_completionAdvanceInProgress || _queue.isEmpty) return;

    // If we landed on the last track and repeat is off, stop cleanly.
    if (_queueIndex >= _queue.length - 1 && _repeatMode == PlaybackRepeatMode.off) {
      isPlaying = false;
      _userWantsPlaying = false;
      _publishServiceState();
      notifyListeners();
      return;
    }

    try {
      _userWantsPlaying = true;
      if (audioPlayer.playing) {
        isPlaying = true;
        _publishServiceState();
        notifyListeners();
        return;
      }
      // Incoming may have a source but silent play() Future — fire-and-poll.
      if (audioPlayer.audioSource != null) {
        try {
          audioPlayer.play();
        } catch (_) {}
        for (var i = 0; i < 12 && !audioPlayer.playing; i++) {
          await Future<void>.delayed(Duration(milliseconds: 40 + i * 20));
          if (i % 3 == 0) {
            try {
              audioPlayer.play();
            } catch (_) {}
          }
        }
        if (audioPlayer.playing) {
          isPlaying = true;
          _publishServiceState();
          notifyListeners();
          return;
        }
      }
      // Still silent — hard cut to Engine A for the current queue index.
      final song = currentSong;
      if (song != null) {
        final token = _playbackIntentGate.issue();
        await _playSongInternal(song, queue: _queue, startIndex: _queueIndex, playbackIntentToken: token);
      }
    } catch (e) {
      debugPrint('Post-crossfade continue failed: $e');
      if (_queueIndex < _queue.length - 1) {
        final next = _queue[_queueIndex + 1];
        final token = _playbackIntentGate.issue();
        await _playSongInternal(next, queue: _queue, startIndex: _queueIndex + 1, playbackIntentToken: token);
      }
    }
  }

  Future<void> _advanceAfterCompletion(String completedSongId) {
    if (_completionAdvanceInProgress) return Future<void>.value();
    // Direct path — do not queue behind other source mutations or a stuck token.
    final intentToken = _playbackIntentGate.issue();
    return _advanceAfterCompletionInternal(completedSongId, intentToken);
  }

  Future<void> _advanceAfterCompletionInternal(String completedSongId, int intentToken) async {
    if (_completionAdvanceInProgress) return;
    // Accept if this is the song that just completed (by id match).
    if (completedSongId.isEmpty) return;
    if (currentSong?.id != completedSongId &&
        _lastCompletionSongId != completedSongId) {
      return;
    }
    _completionAdvanceInProgress = true;
    _userWantsPlaying = true;
    final fromSongId = completedSongId;
    final fromIndex = _queueIndex;
    await ResonateDiagnostics.record('completion_advance_attempt', {
      'fromSongId': fromSongId,
      'queueIndex': fromIndex,
      'queueLength': _queue.length,
      'repeatMode': _repeatMode.name,
    });
    try {
      await _finishHistoryEvent(completed: true);
      if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
        _lastCompletionSongId = null;
        currentPosition = Duration.zero;
        await audioPlayer.seek(Duration.zero);
        await audioPlayer.play();
        isPlaying = true;
        await _startHistoryEvent(currentSong!);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('completion_advance_result', {'result': 'repeated', 'songId': currentSong?.id});
        return;
      }
      if (fromIndex < _queue.length - 1) {
        final next = _queue[fromIndex + 1];
        final ok = await _playSongInternal(next, queue: _queue, startIndex: fromIndex + 1, playbackIntentToken: intentToken);
        // Guarantee audible start after auto-advance (no user gesture available).
        if (ok && !audioPlayer.playing && _userWantsPlaying) {
          try {
            final session = await AudioSession.instance;
            await session.setActive(true);
          } catch (_) {}
          try {
            await audioPlayer.seek(Duration.zero);
          } catch (_) {}
          try {
            await audioPlayer.play();
          } catch (_) {}
          isPlaying = audioPlayer.playing || _userWantsPlaying;
          _publishServiceState();
          notifyListeners();
        }
        await ResonateDiagnostics.record('completion_advance_result', {
          'result': ok ? 'advanced' : 'failed',
          'fromSongId': fromSongId,
          'toSongId': currentSong?.id,
          'queueIndex': _queueIndex,
          'playing': audioPlayer.playing,
        });
        return;
      }
      if (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty) {
        final ok = await _playSongInternal(_queue.first, queue: _queue, startIndex: 0, playbackIntentToken: intentToken);
        if (ok && !audioPlayer.playing && _userWantsPlaying) {
          try {
            final session = await AudioSession.instance;
            await session.setActive(true);
          } catch (_) {}
          try {
            await audioPlayer.seek(Duration.zero);
          } catch (_) {}
          try {
            await audioPlayer.play();
          } catch (_) {}
          isPlaying = audioPlayer.playing || _userWantsPlaying;
          _publishServiceState();
          notifyListeners();
        }
        await ResonateDiagnostics.record('completion_advance_result', {
          'result': ok ? 'wrapped' : 'failed',
          'fromSongId': fromSongId,
          'toSongId': currentSong?.id,
          'queueIndex': _queueIndex,
          'playing': audioPlayer.playing,
        });
        return;
      }
      isPlaying = false;
      currentPosition = currentDuration ?? currentPosition;
      await _persistQueue();
      _publishServiceState();
      notifyListeners();
      await ResonateDiagnostics.record('completion_advance_result', {
        'result': 'queue_exhausted',
        'fromSongId': fromSongId,
        'queueIndex': _queueIndex,
      });
    } catch (e) {
      await ResonateDiagnostics.record('completion_advance_result', {
        'result': 'exception',
        'fromSongId': fromSongId,
        'error': e.toString(),
      });
      debugPrint('completion advance failed: $e');
    } finally {
      _completionAdvanceInProgress = false;
    }
  }

  /// Single entry for "this track finished" (completion + watchdog).
  Future<void> onTrackEnded(String completedSongId) => _advanceAfterCompletion(completedSongId);

  /// Jump to any index in the current queue and start playback.
  Future<bool> playQueueIndex(int index) {
    if (_queue.isEmpty || index < 0 || index >= _queue.length) {
      return Future<bool>.value(false);
    }
    final intentToken = _playbackIntentGate.issue();
    _automaticCrossfadeInFlight = false;
    _crossfadeInProgress = false;
    _completionAdvanceInProgress = false;
    _lastCompletionSongId = null;
    return _serializePlayback(
      () => _playSongInternal(
        _queue[index],
        queue: _queue,
        startIndex: index,
        playbackIntentToken: intentToken,
      ),
      command: 'play',
      source: 'normal_player',
      userInitiated: true,
      intentToken: intentToken,
      onSuperseded: () async => false,
    );
  }

  Uri _audioUri(String value) { final path = value.trim(); if (path.startsWith('content://') || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('file://')) return Uri.parse(path); return Uri.file(path); }

  Future<void> _stopBoth() async { try { await _playerA.stop(); } catch (_) {} try { await _playerB.stop(); } catch (_) {} try { await _playerA.setLoopMode(LoopMode.off); } catch (_) {} try { await _playerB.setLoopMode(LoopMode.off); } catch (_) {} try { await _playerA.setVolume(1.0); } catch (_) {} try { await _playerB.setVolume(1.0); } catch (_) {} }

  Future<void> _enableEffects(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud) async {
    try { await _audioEffectsController.activateFor(player); } catch (e) { debugPrint('Audio effects activation failed: $e'); }
  }

  Future<T> _serializePlayback<T>(Future<T> Function() operation, {required String command, required String source, bool userInitiated = false, int? intentToken, Future<T> Function()? onSuperseded}) async {
  final effectiveIntent = intentToken ?? (userInitiated ? _playbackIntentGate.issue() : _playbackIntentGate.currentToken);
  if (userInitiated) {
    _authority.markExternalUserCommand(source, command);
    unawaited(ResonateDiagnostics.record('playback_command_accepted', {'command': command, 'source': source, 'intentToken': effectiveIntent}));
  }
  // Phase 4 hardened: user play/next/previous/toggle/pause/stop/seek run immediately
  // (transport lane) so they cannot sit behind a stuck source queue.
  final transportPriority = userInitiated && const {
    'toggle', 'pause', 'stop', 'seek', 'play', 'next', 'previous',
  }.contains(command);
  await ResonateDiagnostics.record('playback_operation_queued', {
    'command': command,
    'source': source,
    'userInitiated': userInitiated,
    'intentToken': effectiveIntent,
    'lane': transportPriority ? 'transport_priority' : 'source_serialized',
  });
  if (transportPriority) return _playbackCoordinator.runTransport(operation);
  return _playbackCoordinator.runSourceMutation(
    operation,
    command: command,
    supersedePending: userInitiated && const {'play', 'next', 'previous'}.contains(command),
    onSuperseded: onSuperseded,
  );
}

  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    _lastCompletionSongId = null;
    return _serializePlayback(
      () => _playSongInternal(song, queue: queue, startIndex: startIndex, playbackIntentToken: intentToken),
      command: 'play', source: 'normal_player', userInitiated: true, intentToken: intentToken,
      onSuperseded: () async => false,
    );
  }

  Future<bool> _playSongInternal(Song song, {List<Song>? queue, int startIndex = 0, bool resume = false, int? playbackIntentToken}) async {
    await _visibility.load();
    if (_visibility.isRestricted && !_visibility.isVisible(song.id)) {
      await ResonateDiagnostics.record('playback_rejected_outside_library_scope', {
        'songId': song.id,
        'stage': 'play_song_internal',
      });
      return false;
    }
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    if (song.filePath.trim().isEmpty) return false;

    // Phase 2: non-crossfade play always on Engine A (rebind if we were on B).
    _ensureEngineA(reason: 'play_song_internal');
    final target = _playerA;
    final targetEq = _equalizerA;
    final targetLoud = _loudnessA;
    final outgoing = null; // never hand off from B on the normal path

    _loadingSource = true;
    _userWantsPlaying = true;

    Future<void> step(String name, [Map<String, Object?> extra = const {}]) async {
      await ResonateDiagnostics.record('playback_play_step', {
        'step': name,
        'songId': song.id,
        'intentToken': intentToken,
        ...extra,
      });
    }

    Future<bool> timed(String label, Future<void> future, {int ms = 8000}) async {
      try {
        await future.timeout(Duration(milliseconds: ms));
        return true;
      } catch (e) {
        await ResonateDiagnostics.record('playback_play_step', {
          'step': 'timeout_or_error',
          'label': label,
          'error': e.toString(),
          'songId': song.id,
        });
        debugPrint('playback timed/error $label: $e');
        return false;
      }
    }

    Future<T?> timedValue<T>(String label, Future<T> future, {int ms = 8000}) async {
      try {
        return await future.timeout(Duration(milliseconds: ms));
      } catch (e) {
        await ResonateDiagnostics.record('playback_play_step', {
          'step': 'timeout_or_error',
          'label': label,
          'error': e.toString(),
          'songId': song.id,
        });
        debugPrint('playback timed/error $label: $e');
        return null;
      }
    }

    try {
      _crossfadeInProgress = false;
      _automaticCrossfadeInFlight = false;
      unawaited(_finishHistoryEvent());
      await step('begin');

      // Quiet B; pause A only if needed. Avoid stop() — drops focus on some OEMs.
      try {
        await _playerB.pause();
      } catch (_) {}
      try {
        await _playerB.setVolume(0.0);
      } catch (_) {}
      try {
        if (target.playing) await target.pause();
      } catch (_) {}

      final requested = queue != null && queue.isNotEmpty ? List<Song>.from(queue) : <Song>[song];
      final normalized = requested.where((s) => s.filePath.trim().isNotEmpty).toList();
      if (normalized.isEmpty) return false;

      var selectedIndex = normalized.indexWhere((s) => s.id == song.id);
      if (selectedIndex < 0) {
        selectedIndex = startIndex.clamp(0, normalized.length - 1).toInt();
      }
      final selectedSong = normalized[selectedIndex];

      final nextQueue = _shuffleEnabled && normalized.length > 1
          ? () {
              final selected = normalized[selectedIndex];
              final upcoming = <Song>[...normalized]..removeAt(selectedIndex)..shuffle(Random());
              return <Song>[selected, ...upcoming];
            }()
          : normalized;
      final nextIndex = _shuffleEnabled && normalized.length > 1 ? 0 : selectedIndex;

      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (e) {
        debugPrint('AudioSession setActive (pre-source) failed: $e');
      }

      await timed('setLoopMode', target.setLoopMode(LoopMode.off), ms: 2000);
      await step('set_source_start', {'path': selectedSong.filePath});

      final durationFromSource = await timedValue<Duration?>(
        'setAudioSource',
        target.setAudioSource(
          AudioSource.uri(_audioUri(selectedSong.filePath), tag: selectedSong),
        ),
        ms: 15000,
      );
      await step('set_source_done', {
        'durationMs': durationFromSource?.inMilliseconds,
        'processingState': target.processingState.name,
      });

      // Commit UI state immediately so library shows the selected track.
      _queue = nextQueue;
      _queueIndex = nextIndex;
      currentSong = _queue[_queueIndex];
      _activeIsA = true;
      _lastCompletionSongId = null;
      currentDuration = durationFromSource ?? currentSong!.duration;
      currentPosition = Duration.zero;
      _userWantsPlaying = true;
      await _persistQueue();
      notifyListeners();
      _publishServiceState();

      if (resume && _resumeSongId == currentSong!.id && _resumePositionMs > 0) {
        final durationMs = currentDuration?.inMilliseconds ?? _resumePositionMs;
        final safeResume = _resumePositionMs.clamp(0, durationMs).toInt();
        await timed('seek_resume', target.seek(Duration(milliseconds: safeResume)), ms: 3000);
        currentPosition = Duration(milliseconds: safeResume);
      } else {
        await timed('seek_zero', target.seek(Duration.zero), ms: 3000);
      }

      await timed('setVolume', target.setVolume(1.0), ms: 2000);

      // Effects after source is up — never block play on effects failure/slowness.
      unawaited(_enableEffects(target, targetEq, targetLoud));

      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}

      await step('play_loop_start', {'processingState': target.processingState.name});

      // Phase 6: on this OEM, await play() often never completes even when audio
      // is already running (diagnostics showed TimeoutException + playing:true).
      // Fire play without awaiting the Future; poll player.playing instead.
      var started = false;
      for (var attempt = 0; attempt < 16; attempt++) {
        if (attempt == 0 || attempt == 4 || attempt == 8) {
          try {
            // ignore: unawaited_futures
            target.play();
          } catch (e) {
            debugPrint('play() fire attempt $attempt failed: $e');
          }
        }
        if (target.playing) {
          started = true;
          break;
        }
        if (attempt == 6 || attempt == 12) {
          await timed('reseek_$attempt', target.seek(Duration.zero), ms: 1500);
          try {
            target.play();
          } catch (_) {}
        }
        await Future<void>.delayed(Duration(milliseconds: 40 + attempt * 25));
      }

      isPlaying = started || target.playing;
      _userWantsPlaying = true;
      await step('play_loop_end', {
        'started': started,
        'playing': target.playing,
        'processingState': target.processingState.name,
        'positionMs': target.position.inMilliseconds,
        'strategy': 'fire_and_poll',
      });

      // History must not block the play path.
      unawaited(_startHistoryEvent(currentSong!));
      _publishServiceState();
      notifyListeners();

      if (!target.playing) {
        final kickSongId = selectedSong.id;
        unawaited(Future<void>.delayed(const Duration(milliseconds: 200), () async {
          if (!_userWantsPlaying || currentSong?.id != kickSongId) return;
          try {
            final session = await AudioSession.instance;
            await session.setActive(true);
          } catch (_) {}
          try {
            await target.seek(Duration.zero);
          } catch (_) {}
          try {
            target.play();
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (target.playing) {
            isPlaying = true;
            _publishServiceState();
            notifyListeners();
          }
          await ResonateDiagnostics.record('playback_play_step', {
            'step': 'deferred_kick',
            'songId': kickSongId,
            'playing': target.playing,
            'processingState': target.processingState.name,
          });
        }));
      }

      if (outgoing != null) {
        try {
          await outgoing.pause();
        } catch (_) {}
        try {
          await outgoing.setVolume(0.0);
        } catch (_) {}
      }

      await ResonateDiagnostics.record('playback_engine_handoff', {
        'engine': 'A',
        'songId': currentSong!.id,
        'playing': target.playing,
        'processingState': target.processingState.name,
      });
      return true;
    } catch (e, stack) {
      isPlaying = false;
      _userWantsPlaying = false;
      debugPrint('Error playing song: $e');
      debugPrint('$stack');
      await ResonateDiagnostics.record('playback_operation_failed', {
        'songId': song.id,
        'error': e.toString(),
        'intentToken': intentToken,
      });
      _publishServiceState();
      notifyListeners();
      return false;
    } finally {
      _loadingSource = false;
    }
  }

  Future<void> _startHistoryEvent(Song song) async {
    await _queueHistoryOperation(() async {
      if (_activeHistoryEvent?.songId == song.id) return;
      final event = ListeningEvent(id: '${DateTime.now().microsecondsSinceEpoch}_${song.id}', songId: song.id, previousSongId: _queueIndex > 0 ? _queue[_queueIndex - 1].id : null, startedAt: DateTime.now(), durationPlayedMs: currentPosition.inMilliseconds, songDurationMs: song.duration.inMilliseconds, completionRatio: 0, completed: false, skipped: false);
      _activeHistoryEvent = event; _activeHistoryPositionMs = currentPosition.inMilliseconds; _resumePositionMs = currentPosition.inMilliseconds; _resumeSongId = song.id;
      try { final inserted = await _database.insertListeningEvent(event); final playCount = await _database.updateSongPlayCount(song.id); if (inserted < 0 || playCount < 0) { unawaited(ResonateDiagnostics.record('listening_history_start_failed', {'songId': song.id, 'insertResult': inserted, 'playCountResult': playCount})); } } catch (e, stack) { debugPrint('Listening history start failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_start_failed', {'songId': song.id, 'error': e.toString(), 'stack': stack.toString()})); }
    });
  }

  Future<void> _finishHistoryEvent({bool completed = false}) async {
    await _queueHistoryOperation(() async {
      final event = _activeHistoryEvent; if (event == null) return;
      final total = event.songDurationMs > 0 ? event.songDurationMs : (currentDuration?.inMilliseconds ?? 0); final position = _activeHistoryPositionMs.clamp(0, total > 0 ? total : 1).toInt(); final ratio = total <= 0 ? 0.0 : (position / total).clamp(0.0, 1.0).toDouble(); final wasCompleted = completed || ratio >= .90;
      final updated = ListeningEvent(id: event.id, songId: event.songId, previousSongId: event.previousSongId, startedAt: event.startedAt, endedAt: DateTime.now(), durationPlayedMs: position, songDurationMs: total, completionRatio: ratio, completed: wasCompleted, skipped: !wasCompleted && position > 0, skipPositionMs: !wasCompleted && position > 0 ? position : null);
      _activeHistoryEvent = null; _activeHistoryPositionMs = 0;
      if (wasCompleted) { _resumePositionMs = 0; _resumeSongId = null; unawaited(SharedPreferences.getInstance().then((prefs) async { await prefs.remove(_resumePositionKey); await prefs.remove(_resumeSongIdKey); }).catchError((error) { debugPrint('Playback resume clear failed: $error'); })); } else { _persistResumePosition(force: true); }
      try { final updatedRows = await _database.updateListeningEvent(updated); if (updatedRows < 0 || updatedRows == 0) { unawaited(ResonateDiagnostics.record('listening_history_finish_failed', {'songId': event.songId, 'eventId': event.id, 'updateResult': updatedRows})); } } catch (e, stack) { debugPrint('Listening history finish failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_finish_failed', {'songId': event.songId, 'error': e.toString(), 'stack': stack.toString()})); }
    });
  }

  Future<void> _queueHistoryOperation(Future<void> Function() operation) {
    // Every history mutation must stay on the same serial chain. The old
    // active-operation shortcut allowed start/finish writes to overlap.
    final next = _historySerial.then((_) async {
      _historyOperationActive = true;
      try { await operation(); } finally { _historyOperationActive = false; }
    });
    _historySerial = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<bool> enqueueSongs(List<Song> songs) async { await _visibility.load(); final additions = songs.where((s) => _visibility.isVisible(s.id) && s.filePath.trim().isNotEmpty && !_queue.any((q) => q.id == s.id)).toList(); if (additions.isEmpty) return false; if (_shuffleEnabled && additions.length > 1) additions.shuffle(Random()); _queue.addAll(additions); await _persistQueue(); notifyListeners(); return true; }
  Future<bool> addToQueue(Song song) => enqueueSongs([song]);
  Future<bool> playNext(Song song) async { await _visibility.load(); if (!_visibility.isVisible(song.id) || song.filePath.trim().isEmpty || currentSong?.id == song.id || _queue.any((q) => q.id == song.id)) return false; final insertAt = (_queueIndex + 1).clamp(0, _queue.length).toInt(); _queue.insert(insertAt, song); await _persistQueue(); notifyListeners(); return true; }
  Future<bool> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length || index == _queueIndex) return false;
    _queue.removeAt(index);
    if (index < _queueIndex) _queueIndex -= 1;
    await _persistQueue();
    notifyListeners();
    return true;
  }
  Future<bool> reorderQueue(int oldIndex, int newIndex) async { if (oldIndex <= _queueIndex || oldIndex >= _queue.length) return false; if (newIndex > oldIndex) newIndex--; newIndex = newIndex.clamp(_queueIndex + 1, _queue.length - 1).toInt(); final item = _queue.removeAt(oldIndex); _queue.insert(newIndex, item); await _persistQueue(); notifyListeners(); return true; }
  void clearUpcomingQueue() { if (_queueIndex >= _queue.length - 1) return; _queue = [..._queue.take(_queueIndex + 1)]; unawaited(_persistQueue()); notifyListeners(); }

  Future<void> _loadSingle(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud, Song song, {bool start = true}) async {
    await player.setLoopMode(LoopMode.off);
    await player.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song));
    unawaited(_enableEffects(player, eq, loud));
    await player.setVolume(start ? 1.0 : 0.0);
    if (start) {
      // Fire-and-poll — await play() hangs on some OEMs.
      try {
        player.play();
      } catch (_) {}
      for (var i = 0; i < 12 && !player.playing; i++) {
        await Future<void>.delayed(Duration(milliseconds: 40 + i * 20));
        if (i % 3 == 0) {
          try {
            player.play();
          } catch (_) {}
        }
      }
    }
  }

  Future<bool> performTrueCrossfade({required int milliseconds, String fadeType = 'linear'}) => _serializePlayback(() => _performTrueCrossfade(milliseconds: milliseconds, fadeType: fadeType, generation: _authority.beginAutomatic('crossfade')), command: 'crossfade', source: 'automatic_transition');

  Future<bool> _performTrueCrossfade({required int milliseconds, String fadeType = 'linear', required int generation, int? playbackIntentToken}) async {
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    if (!_playbackIntentGate.isCurrent(intentToken)) return false;
    if (!canCrossfadeNext || currentSong == null || !audioPlayer.playing) return false;
    final nextIndex = _queueIndex + 1; final nextSong = _queue[nextIndex]; if (nextSong.filePath.trim().isEmpty) return false;
    _crossfadeInProgress = true; final outgoing = audioPlayer; final outgoingSong = currentSong; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _volume;
    try {
      await outgoing.setLoopMode(LoopMode.off);
      final alreadyPreloaded = _preloadedNextSongId == nextSong.id;
      if (!alreadyPreloaded) {
        try {
          await incoming.stop();
        } catch (_) {}
        await _loadSingle(incoming, incomingEq, incomingLoud, nextSong, start: false);
      } else {
        await ResonateDiagnostics.record('crossfade_using_preload', {
          'songId': nextSong.id,
        });
        try {
          await incoming.seek(Duration.zero);
        } catch (_) {}
      }
      await incoming.setVolume(0.0);
      // Fire-and-poll play on B — await play() can hang and block auto-next forever.
      try {
        incoming.play();
      } catch (_) {}
      var incomingStarted = incoming.playing;
      for (var i = 0; i < 15 && !incomingStarted; i++) {
        if (incoming.playing) {
          incomingStarted = true;
          break;
        }
        if (i == 4 || i == 9) {
          try {
            await incoming.seek(Duration.zero);
          } catch (_) {}
          try {
            incoming.play();
          } catch (_) {}
        }
        await Future<void>.delayed(Duration(milliseconds: 50 + i * 20));
        incomingStarted = incoming.playing;
      }
      if (!incomingStarted) {
        _preloadedNextSongId = null;
        throw StateError('crossfade incoming engine failed to start');
      }
      final total = milliseconds.clamp(500, 12000).toInt(); final steps = (total / 50).round().clamp(10, 240).toInt();
      for (var i = 1; i <= steps; i++) {
        if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'fade', 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
        final linear = i / steps; final t = switch (fadeType) { 'ease_in' => linear * linear, 'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)), 'ease_in_out' => linear < 0.5 ? 2.0 * linear * linear : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0, _ => linear };
        await outgoing.setVolume(master * (1.0 - t)); await incoming.setVolume(master * t); await Future<void>.delayed(Duration(milliseconds: (total / steps).round()));
      }
      if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'commit', 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
      // Finish the outgoing history record while currentSong still refers to it.
      // Mutating currentSong first caused history to be attributed to the next track.
      await _finishHistoryEvent();
      if (!_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} return false; }
      await outgoing.pause(); await outgoing.setVolume(master); await incoming.setLoopMode(LoopMode.off); await incoming.setVolume(master);
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active
      _queueIndex = nextIndex; currentSong = nextSong; _lastCompletionSongId = null; currentDuration = nextSong.duration; currentPosition = incoming.position; isPlaying = incoming.playing;
      await _persistQueue(); _bindActivePlayerStreams(); await _startHistoryEvent(nextSong); _publishServiceState(); notifyListeners(); await outgoing.stop();
      _preloadedNextSongId = null;
      await ResonateDiagnostics.record('crossfade_committed', {
        'outgoingSongId': outgoingSong?.id,
        'incomingSongId': nextSong.id,
        'queueIndex': _queueIndex,
        'intentToken': intentToken,
        'activeEngine': _activeIsA ? 'A' : 'B',
      });
      return true;
    } catch (e, stack) {
      debugPrint('True crossfade failed: $e'); debugPrint('$stack');
      try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {}
      await ResonateDiagnostics.record('crossfade_failed', {'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'error': e.toString(), 'intentToken': intentToken});
      if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) return false;
      try { await outgoing.stop(); await _playSongInternal(nextSong, queue: _queue, startIndex: nextIndex, playbackIntentToken: intentToken); return true; } catch (fallbackError) { debugPrint('Crossfade fallback failed: $fallbackError'); await ResonateDiagnostics.record('crossfade_fallback_failed', {'incomingSongId': nextSong.id, 'error': fallbackError.toString(), 'intentToken': intentToken}); return false; }
    } finally {
      _crossfadeInProgress = false;
      notifyListeners();

      // Critical fix: if the outgoing track reached completed while we were
      // crossfading, the normal completion path was suppressed. Force
      // continuation now that the hand-off is finished.
      if (_completionObservedDuringCrossfade) {
        _completionObservedDuringCrossfade = false;
        if (!_completionAdvanceInProgress) {
          unawaited(_ensureContinueAfterCrossfade());
        }
      } else {
        _completionObservedDuringCrossfade = false;
      }
    }
  }


  /// Phase 4: user transport always wins over automatic work.
  void _cancelAutomaticPlaybackWork() {
    _automaticCrossfadeInFlight = false;
    _crossfadeInProgress = false;
    _completionAdvanceInProgress = false;
    _completionObservedDuringCrossfade = false;
    _preloadedNextSongId = null;
    _crossfadePreloadInFlight = false;
    _endOfTrackWatchdog?.cancel();
    _endOfTrackWatchdog = null;
  }

  /// Explicit play/resume — used by media-session onPlay and as the play half of toggle.
  /// Never toggles; never pauses.
  Future<void> resumePlayback({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      try {
        _userWantsPlaying = true;
        if (audioPlayer.audioSource != null) {
          try {
            final session = await AudioSession.instance;
            await session.setActive(true);
          } catch (_) {}
          // If we are sitting on a completed source, seek to zero first.
          if (audioPlayer.processingState == ProcessingState.completed) {
            try {
              await audioPlayer.seek(Duration.zero);
            } catch (_) {}
          }
          for (var attempt = 0; attempt < 12; attempt++) {
            if (attempt == 0 || attempt == 3 || attempt == 6) {
              try {
                audioPlayer.play();
              } catch (e) {
                debugPrint('resumePlayback play() fire $attempt failed: $e');
              }
            }
            if (audioPlayer.playing) break;
            await Future<void>.delayed(Duration(milliseconds: 40 + attempt * 25));
          }
          isPlaying = audioPlayer.playing || _userWantsPlaying;
          _publishServiceState();
          notifyListeners();
          return;
        }
        if (currentSong != null) {
          await _playSongInternal(
            currentSong!,
            queue: _queue.isEmpty ? null : _queue,
            startIndex: _queueIndex,
            resume: true,
            playbackIntentToken: intentToken,
          );
        }
      } catch (e) {
        debugPrint('resumePlayback failed: $e');
      }
    }, command: 'play', source: source, userInitiated: true, intentToken: intentToken);
  }

  Future<void> togglePlayPause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      try {
        // Decide from NATIVE state only. Optimistic isPlaying must not flip a
        // failed play() into a pause — that is the library-tap / auto-next bug.
        if (audioPlayer.playing) {
          _userWantsPlaying = false;
          await audioPlayer.pause();
          isPlaying = false;
          _persistResumePosition(force: true);
          _publishServiceState();
          notifyListeners();
          return;
        }
        // Not natively playing → always play/resume.
        _userWantsPlaying = true;
        if (audioPlayer.audioSource != null) {
          try {
            final session = await AudioSession.instance;
            await session.setActive(true);
          } catch (_) {}
          if (audioPlayer.processingState == ProcessingState.completed) {
            try {
              await audioPlayer.seek(Duration.zero);
            } catch (_) {}
          }
          for (var attempt = 0; attempt < 12; attempt++) {
            if (attempt == 0 || attempt == 3 || attempt == 6) {
              try {
                audioPlayer.play();
              } catch (e) {
                debugPrint('toggle play() fire $attempt failed: $e');
              }
            }
            if (audioPlayer.playing) break;
            await Future<void>.delayed(Duration(milliseconds: 40 + attempt * 25));
          }
          isPlaying = audioPlayer.playing || _userWantsPlaying;
          _publishServiceState();
          notifyListeners();
        } else if (currentSong != null) {
          await _playSongInternal(
            currentSong!,
            queue: _queue.isEmpty ? null : _queue,
            startIndex: _queueIndex,
            resume: true,
            playbackIntentToken: intentToken,
          );
        }
      } catch (e) {
        debugPrint('Playback toggle failed: $e');
      }
    }, command: 'toggle', source: source, userInitiated: true, intentToken: intentToken);
  }

  Future<void> pause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      try {
        _userWantsPlaying = false;
        await audioPlayer.pause();
        isPlaying = false;
        _persistResumePosition(force: true);
        _publishServiceState();
        notifyListeners();
      } catch (_) {}
    }, command: 'pause', source: source, userInitiated: true, intentToken: intentToken);
  }

  Future<void> stop({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      if (!_playbackIntentGate.isCurrent(intentToken)) return;
      await _finishHistoryEvent();
      await _stopBoth();
      isPlaying = false;
      currentPosition = Duration.zero;
      _publishServiceState();
      notifyListeners();
    }, command: 'stop', source: source, userInitiated: true, intentToken: intentToken);
  }

  Future<void> nextSong({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();

    return _serializePlayback(
      () async {
        // Do not bail on token churn — user next must always attempt advance.
        if (_queue.isEmpty) return;

        if (_queueIndex >= _queue.length - 1) {
          if (_repeatMode == PlaybackRepeatMode.all) {
            await _playSongInternal(_queue.first, queue: _queue, startIndex: 0, playbackIntentToken: intentToken);
          } else if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
            await _playSongInternal(currentSong!, queue: _queue, startIndex: _queueIndex, playbackIntentToken: intentToken);
          }
          return;
        }

        final nextIndex = _queueIndex + 1;
        // Core reliability: next is always a direct load on Engine A (no crossfade).
        // Crossfade remains available via explicit performTrueCrossfade / Autopilot later.
        await _playSongInternal(
          _queue[nextIndex],
          queue: _queue,
          startIndex: nextIndex,
          playbackIntentToken: intentToken,
        );
      },
      command: 'next',
      source: source,
      userInitiated: true,
      intentToken: intentToken,
      onSuperseded: () async {},
    );
  }

  Future<void> previousSong({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();

    return _serializePlayback(
      () async {
        if (_queueIndex > 0) {
          final previousIndex = _queueIndex - 1;
          await _playSongInternal(_queue[previousIndex], queue: _queue, startIndex: previousIndex, playbackIntentToken: intentToken);
        } else {
          await audioPlayer.seek(Duration.zero);
          currentPosition = Duration.zero;
          if (_activeHistoryEvent != null) _activeHistoryPositionMs = 0;
          _persistResumePosition(force: true);
          notifyListeners();
          _publishServiceState();
        }
      },
      command: 'previous',
      source: source,
      userInitiated: true,
      intentToken: intentToken,
      onSuperseded: () async {},
    );
  }
  Future<void> seek(Duration position, {String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(
      () async {
        if (!_playbackIntentGate.isCurrent(intentToken)) return;
        try {
          final duration = audioPlayer.duration ?? currentDuration ?? Duration.zero;
          final safe = Duration(
            milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds).toInt(),
          );
          await audioPlayer.seek(safe);
          currentPosition = safe;
          if (_activeHistoryEvent != null) {
            _activeHistoryPositionMs = safe.inMilliseconds;
          }
          _persistResumePosition(force: true);
          _publishServiceState();
          notifyListeners();
        } catch (e) {
          debugPrint('Seek failed: $e');
        }
      },
      command: 'seek',
      source: source,
      userInitiated: true,
      intentToken: intentToken,
    );
  }
  Future<void> _syncSystemVolume() async {
    try {
      final raw = await _systemVolumeChannel.invokeMethod<dynamic>('getSystemVolume');
      if (raw is Map) {
        final current = (raw['current'] as num?)?.toDouble() ?? 0;
        final max = (raw['max'] as num?)?.toDouble() ?? 0;
        if (max > 0) {
          final next = (current / max).clamp(0.0, 1.0).toDouble();
          if ((next - _volume).abs() > 0.001) { _volume = next; notifyListeners(); }
        }
      }
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    try {
      await _systemVolumeChannel.invokeMethod('setSystemVolume', {'value': _volume});
      await audioPlayer.setVolume(1.0);
      await inactivePlayer.setVolume(1.0);
    } catch (_) {}
    notifyListeners();
  }
  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async { if (songs.isEmpty) { await _finishHistoryEvent(); _queue = <Song>[]; _queueIndex = 0; await _persistQueue(); notifyListeners(); return; } final index = startIndex.clamp(0, songs.length - 1).toInt(); await playSong(songs[index], queue: songs, startIndex: index); }
  Stream<Duration?> get durationStream => audioPlayer.durationStream;
  @override
  void dispose() {
    _systemVolumePollTimer?.cancel();
    _endOfTrackWatchdog?.cancel();
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
