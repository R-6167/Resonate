import 'dart:async';
import 'dart:io' show Platform;
import 'dart:convert';
import '../services/intelligence_seek_memory.dart';
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/dj_analysis.dart';
import '../models/listening_event.dart';
import '../services/audio_service_handler.dart';
import '../services/database_helper.dart';
import '../services/dj_analysis_service.dart';
import '../services/dj_bpm_estimator.dart';
import '../services/dj_transition_planner.dart';
import '../services/dj_transition_memory.dart';
import '../services/playback_authority.dart';
import '../services/playback_intent_gate.dart';
import '../services/resonate_diagnostics.dart';
import '../services/library_visibility_store.dart';
import '../services/audio_effects_bridge.dart';
import '../services/dj_sfx_rack.dart';
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
  /// Digital gain from EQ preamp (1.0 = 0 dB). Attenuation only via this path.
  double _eqPreampScale = 1.0;
  /// Optional listener for Android audio session (Resonate native DSP).
  void Function(int sessionId)? onAndroidSession;
  StreamSubscription<int?>? _sessionASub;
  StreamSubscription<int?>? _sessionBSub;
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
  /// Repeat-one + crossfade: seamless loop via idle engine (no queue advance).
  bool _repeatSelfHandoffArmed = false;
  bool _repeatSelfHandoffInFlight = false;
  String? _repeatSelfTargetSongId;
  /// DJ Mode Step 2 — only true when DjModeProvider master + beat-align are on.
  bool _djBeatAlignActive = false;
  bool _djTempoMatchActive = false;
  int _djMaxStretchPercent = 12;
  bool _djSfxActive = false;
  bool _djSfxEngaged = false;
  final DjSfxRack _djSfxRack = DjSfxRack();
  DjAnalysisService? _djAnalysis;
  double? _djStretchSpeedOut;
  double? _djStretchSpeedIn;
  DateTime? _lastDjHandoffAt;
  String? _lastDjFromId;
  String? _lastDjToId;
  String? _lastDjStrategy;
  /// Soft energy-bridge bias applied to the next crossfade length (ms).
  int _lastDjCrossfadeBiasMs = 0;
  double _lastDjEnergyScore = 0.5;

  int? _androidSdkInt;
  int _gaplessWindowStart = 0;
  List<String> _gaplessWindowIds = const [];
  bool _gaplessSourceActive = false;
  bool _transportInFlight = false;
  bool _userWantsPlaying = false;
  bool _loadingSource = false;
  DateTime? _lastPlayKickAt;
  DateTime? _lastSilentRecoverAt;
  int _resumePositionMs = 0;
  String? _resumeSongId;
  DateTime? _lastResumePersist;
  Timer? _systemVolumePollTimer;
  Timer? _endOfTrackWatchdog;
  String? _lastCompletionSongId;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSubscription;
  DateTime? _lastRouteRecoverAt;

  /// True while system asked us to duck (notification / nav / transient).
  bool _isDucked = false;
  /// When exclusive focus was lost (call / other media) — used for long-call gate.
  DateTime? _focusLostAt;
  int _volumeFadeGen = 0;
  static const double _duckLevel = 0.32;
  static const int _duckFadeMs = 180;
  /// Short transport fade for user pause / resume (keeps next/seek snappy).
  static const int _transportFadeMs = 220;
  static const Duration _autoResumeMaxFocusLoss = Duration(minutes: 3);

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
  bool get canCrossfadeNext {
    if (_crossfadeInProgress || _queue.isEmpty || _queueIndex < 0) return false;
    if (_repeatMode == PlaybackRepeatMode.one) return false;
    if (_queueIndex < _queue.length - 1) return true;
    if (_repeatMode == PlaybackRepeatMode.all && _queue.length > 1) return true;
    return false;
  }

  /// Seamless loop: same song on the idle engine when repeat-one + crossfade.
  bool get canRepeatSelfHandoff {
    if (!_crossfadeEnabled) return false;
    if (_repeatMode != PlaybackRepeatMode.one) return false;
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _transportInFlight) {
      return false;
    }
    if (currentSong == null || currentSong!.filePath.trim().isEmpty) return false;
    if (!audioPlayer.playing && !_userWantsPlaying) return false;
    return true;
  }

  Song? get _crossfadeTargetSong {
    if (_queue.isEmpty || _queueIndex < 0) return null;
    if (_repeatMode == PlaybackRepeatMode.one) return null;
    if (_queueIndex < _queue.length - 1) return _queue[_queueIndex + 1];
    if (_repeatMode == PlaybackRepeatMode.all && _queue.length > 1) return _queue.first;
    return null;
  }

  int get _crossfadeTargetIndex {
    if (_queueIndex < _queue.length - 1) return _queueIndex + 1;
    if (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty) return 0;
    return _queueIndex;
  }

  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeDurationMs => _crossfadeDurationMs;
  String get crossfadeFadeType => _crossfadeFadeType;
  String get activeEngineLabel => _authority.engineLabel(this);
  bool get transitionInProgress => _crossfadeInProgress || _automaticCrossfadeInFlight;

  /// Phase 2: normal listening is always Engine A. Engine B is only for an
  /// in-progress crossfade (or a track that was handed off via crossfade).
  bool get isEngineA => _activeIsA;

  /// True when we have a saved mid-track position for the current queue song.
  bool get canContinueListening {
    final song = currentSong;
    if (song == null) return false;
    if (_resumeSongId != song.id) return false;
    if (_resumePositionMs < 1500) return false;
    final dur = (currentDuration ?? song.duration).inMilliseconds;
    if (dur > 0 && _resumePositionMs >= dur - 2000) return false;
    return true;
  }

  int get resumePositionMs => _resumePositionMs;
  String? get resumeSongId => _resumeSongId;

  /// Resume the restored queue song from the last saved position.
  Future<bool> continueListening({String source = 'continue_listening'}) {
    final song = currentSong;
    if (song == null) return Future<bool>.value(false);
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(
      () => _playSongInternal(
        song,
        queue: _queue.isNotEmpty ? _queue : [song],
        startIndex: _queueIndex.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1),
        resume: true,
        playbackIntentToken: intentToken,
      ),
      command: 'play',
      source: source,
      userInitiated: true,
      intentToken: intentToken,
    );
  }

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
    unawaited(() async {
      try {
        await _playerB.setSpeed(1.0);
      } catch (_) {}
      try {
        await _playerA.setSpeed(1.0);
      } catch (_) {}
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
  static const _resumeMapKey = 'playback_resume_map_v1';
  final Map<String, int> _resumeBySongId = {};
  static const MethodChannel _systemVolumeChannel = MethodChannel('com.aetherion.resonate/media_store');

  MusicProvider({this.audioHandler}) {
    _equalizerA = AndroidEqualizer();
    _equalizerB = AndroidEqualizer();
    _loudnessA = AndroidLoudnessEnhancer();
    _loudnessB = AndroidLoudnessEnhancer();
    _audioEffectsController = AudioEffectsController(equalizerA: _equalizerA, equalizerB: _equalizerB, loudnessA: _loudnessA, loudnessB: _loudnessB);
    // Reconnected: Equalizer + LoudnessEnhancer in the pipeline (was the 34h-stable path).
    // Extra native effects stay lazy — attach only after a session exists.
    _playerA = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerA, _loudnessA]));
    _playerB = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB, _loudnessB]));
    _sessionASub = _playerA.androidAudioSessionIdStream.listen((id) {
      try {
        if (id != null && id > 0 && _activeIsA) onAndroidSession?.call(id);
      } catch (e) {
        debugPrint('onAndroidSession A failed: $e');
      }
    }, onError: (e) => debugPrint('sessionA stream error: $e'));
    _sessionBSub = _playerB.androidAudioSessionIdStream.listen((id) {
      try {
        if (id != null && id > 0 && !_activeIsA) onAndroidSession?.call(id);
      } catch (e) {
        debugPrint('onAndroidSession B failed: $e');
      }
    }, onError: (e) => debugPrint('sessionB stream error: $e'));
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
      await _loadResumeMap(prefs);
      await _syncSystemVolume();
      // Skip syncSavedAudioEffects at startup — it awaits eq.parameters and
      // then fires during the first play, crashing the Activity.

      if (!const ['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(_crossfadeFadeType)) _crossfadeFadeType = 'linear';
      notifyListeners();
    } catch (e) { debugPrint('Playback settings load failed: $e'); }
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    if (enabled && _queue.length > 1 && _queueIndex < _queue.length - 1) {
      final current = _queue[_queueIndex];
      final upcoming = _queue.sublist(_queueIndex + 1)..shuffle(math.Random());
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


  /// Called by [DjModeProvider]. When [beatAlignActive] is false, crossfade
  /// ignores BPM and behaves exactly as before.
  void configureDjMode({
    required bool beatAlignActive,
    bool tempoMatchActive = false,
    int maxStretchPercent = 12,
    bool sfxActive = false,
    DjAnalysisService? analysis,
  }) {
    final wasActive = _djBeatAlignActive || _djTempoMatchActive;
    _djBeatAlignActive = beatAlignActive;
    _djTempoMatchActive = tempoMatchActive;
    _djMaxStretchPercent = maxStretchPercent.clamp(3, 20);
    _djSfxActive = sfxActive;
    _djAnalysis = analysis;
    if (wasActive && !beatAlignActive && !tempoMatchActive) {
      unawaited(_recoverDjEngineState(reason: 'dj_mode_disabled'));
    }
  }


  /// If UI says playing but engine volume is near zero outside a crossfade, unstick.
  void _maybeRecoverSilentPlayback() {
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    if (!_userWantsPlaying) return;
    try {
      final active = audioPlayer;
      // Playing but muted, or wants play but engine not playing (BT route lag).
      final mutedWhilePlaying =
          active.playing && active.volume < 0.05;
      final wantsButStopped = !active.playing;
      if (!mutedWhilePlaying && !wantsButStopped) return;
      final now = DateTime.now();
      final cooldown = wantsButStopped
          ? const Duration(seconds: 2)
          : const Duration(seconds: 3);
      if (_lastSilentRecoverAt != null &&
          now.difference(_lastSilentRecoverAt!) < cooldown) {
        return;
      }
      _lastSilentRecoverAt = now;
      unawaited(() async {
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}
        await _recoverDjEngineState(reason: mutedWhilePlaying
            ? 'silent_watchdog'
            : 'silent_watchdog_not_playing');
        if (_userWantsPlaying && !audioPlayer.playing) {
          try {
            await audioPlayer.play();
          } catch (_) {}
        }
        try {
          await ResonateDiagnostics.record('playback_volume_unstick', {
            'reason': mutedWhilePlaying ? 'muted' : 'not_playing',
            'volume': audioPlayer.volume,
            'playing': audioPlayer.playing,
            'songId': currentSong?.id,
          });
        } catch (_) {}
      }());
    } catch (_) {}
  }
  /// Restore normal speed + audible volume after DJ handoff mistakes.
  Future<void> _recoverDjEngineState({String reason = 'recover'}) async {
    try {
      await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
    } catch (_) {}
    try {
      await _restoreDjTransitionSfx();
    } catch (_) {}
    try {
      final active = audioPlayer;
      final inactive = inactivePlayer;
      final vol = _eqPreampScale.clamp(0.05, 1.0);
      try {
        await active.setSpeed(1.0);
      } catch (_) {}
      try {
        await inactive.setSpeed(1.0);
      } catch (_) {}
      try {
        if ((_userWantsPlaying || active.playing) && active.volume < vol * 0.85) {
          await active.setVolume(vol);
        }
      } catch (_) {}
      try {
        await inactive.setVolume(0.0);
      } catch (_) {}
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      await ResonateDiagnostics.recordDj(
        stage: 'engine_recover',
        outcome: 'applied',
        reason: reason,
        extra: {
          'activeVolume': active.volume,
          'activePlaying': active.playing,
          'activeEngine': _activeIsA ? 'A' : 'B',
        },
      );
    } catch (e) {
      debugPrint('DJ engine recover failed: $e');
    }
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


  /// Claim media focus before any intentional play. Safe to call often.
  Future<void> _claimAudioFocus({String reason = 'play'}) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      unawaited(ResonateDiagnostics.record('audio_focus_claim', {
        'reason': reason,
        'songId': currentSong?.id,
        'userWantsPlaying': _userWantsPlaying,
      }));
    } catch (e) {
      debugPrint('claimAudioFocus ($reason): $e');
    }
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      // Explicit media focus (same base as .music()): exclusive GAIN so other apps
      // should not mix with us. We soft-duck on duck events; pause+resume on full pause.
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        unawaited(ResonateDiagnostics.record('audio_focus_event', {
          'begin': event.begin,
          'type': event.type.name,
          'userWantsPlaying': _userWantsPlaying,
          'isPlaying': isPlaying,
          'isDucked': _isDucked,
          'songId': currentSong?.id,
        }));
        if (event.begin) {
          if (event.type == AudioInterruptionType.pause) {
            // Calls / exclusive media: pause, keep intent, stamp focus-loss time.
            _focusLostAt = DateTime.now();
            unawaited(pause(source: 'system'));
          } else if (event.type == AudioInterruptionType.duck) {
            // Notifications / nav / transient: soft duck with fade.
            unawaited(_duckForInterruption());
          } else {
            // Unknown transient — prefer duck over a hard stop.
            unawaited(_duckForInterruption());
          }
        } else {
          if (event.type == AudioInterruptionType.duck) {
            if (_userWantsPlaying) unawaited(_unduckAfterInterruption());
          } else if (event.type == AudioInterruptionType.pause) {
            final lostAt = _focusLostAt;
            _focusLostAt = null;
            final lostLong = lostAt != null &&
                DateTime.now().difference(lostAt) > _autoResumeMaxFocusLoss;
            if (lostLong) {
              // Long call: do not surprise-resume; user taps play when ready.
              _userWantsPlaying = false;
              unawaited(ResonateDiagnostics.record('audio_focus_event', {
                'action': 'skip_auto_resume_long_focus_loss',
                'lostMs': lostAt == null
                    ? null
                    : DateTime.now().difference(lostAt).inMilliseconds,
              }));
              return;
            }
            if (_userWantsPlaying) {
              unawaited(_resumeAfterSystemFocus());
            }
          } else if (_userWantsPlaying && _isDucked) {
            unawaited(_unduckAfterInterruption());
          }
        }
      });
      _noisySubscription = session.becomingNoisyEventStream.listen((_) {
        // Headphones unplugged: treat as user-facing pause (do not auto-resume).
        if (isPlaying || _userWantsPlaying) {
          unawaited(pause(source: 'becoming_noisy'));
        }
      });
      // Bluetooth / headset route changes often leave volume or focus stuck silent.
      try {
        await _devicesChangedSubscription?.cancel();
      } catch (_) {}
      _devicesChangedSubscription =
          session.devicesChangedEventStream.listen((_) {
        unawaited(_onAudioRouteChanged());
      });
    } catch (e) {
      debugPrint('Audio session setup failed: $e');
    }
  }


  /// BT/headset route change: re-claim session and force audible volume.
  /// OEMs often take 0.5–3s to settle A2DP; we pulse volume a few times.
  Future<void> _onAudioRouteChanged() async {
    final now = DateTime.now();
    if (_lastRouteRecoverAt != null &&
        now.difference(_lastRouteRecoverAt!) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastRouteRecoverAt = now;
    try {
      await ResonateDiagnostics.record('audio_route_changed', {
        'userWantsPlaying': _userWantsPlaying,
        'isPlaying': isPlaying,
        'crossfade': _crossfadeInProgress,
        'songId': currentSong?.id,
      });
    } catch (_) {}
    if (!_userWantsPlaying) return;
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    try {
      final session = await AudioSession.instance;
      try {
        await session.setActive(true);
      } catch (_) {}
    } catch (_) {}
    for (final delayMs in <int>[200, 700, 1600, 3200]) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (!_userWantsPlaying) return;
      if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
      try {
        await _recoverDjEngineState(reason: 'audio_route_changed');
      } catch (_) {}
      try {
        final active = audioPlayer;
        final vol = (_volume * _eqPreampScale).clamp(0.05, 1.0);
        await active.setVolume(vol);
        if (_userWantsPlaying && !active.playing) {
          try {
            await active.play();
          } catch (_) {}
        }
      } catch (_) {}
    }
    try {
      await ResonateDiagnostics.record('audio_route_recover_done', {
        'playing': audioPlayer.playing,
        'volume': audioPlayer.volume,
        'songId': currentSong?.id,
      });
    } catch (_) {}
  }

  /// Soft-duck both engines so crossfade overlap does not leave one at full level.
  Future<void> _fadePlayerVolume(
    AudioPlayer player,
    double from,
    double to, {
    int durationMs = _duckFadeMs,
    int steps = 6,
  }) async {
    final gen = ++_volumeFadeGen;
    final start = from.clamp(0.0, 1.0);
    final end = to.clamp(0.0, 1.0);
    if ((start - end).abs() < 0.01) {
      try {
        await player.setVolume(end);
      } catch (_) {}
      return;
    }
    final stepMs = (durationMs / steps).round().clamp(16, 80);
    for (var i = 1; i <= steps; i++) {
      if (gen != _volumeFadeGen) return; // superseded by newer fade / transport
      if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
      final t = i / steps;
      final v = start + (end - start) * t;
      try {
        await player.setVolume(v.clamp(0.0, 1.0));
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: stepMs));
    }
  }

  Future<void> _duckForInterruption() async {
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
      // Let the crossfade own volumes; mark ducked so we restore after.
      _isDucked = true;
      return;
    }
    _isDucked = true;
    final target = (_duckLevel * _eqPreampScale).clamp(0.05, 0.45);
    try {
      final aVol = _playerA.volume;
      final bVol = _playerB.volume;
      // Fade active; keep inactive quiet.
      if (_activeIsA) {
        await _fadePlayerVolume(_playerA, aVol, target);
        try {
          await _playerB.setVolume(0.0);
        } catch (_) {}
      } else {
        await _fadePlayerVolume(_playerB, bVol, target);
        try {
          await _playerA.setVolume(0.0);
        } catch (_) {}
      }
      unawaited(ResonateDiagnostics.record('audio_focus_duck', {
        'level': target,
        'engine': _activeIsA ? 'A' : 'B',
      }));
    } catch (_) {
      try {
        await audioPlayer.setVolume(target);
      } catch (_) {}
    }
  }

  Future<void> _unduckAfterInterruption() async {
    if (!_isDucked && audioPlayer.volume >= _eqPreampScale * 0.9) {
      return;
    }
    try {
      if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
        _isDucked = false;
        return;
      }
      final restored = _eqPreampScale.clamp(0.0, 1.0);
      final from = audioPlayer.volume;
      await _fadePlayerVolume(audioPlayer, from, restored);
      try {
        await inactivePlayer.setVolume(0.0);
      } catch (_) {}
      _isDucked = false;
      unawaited(ResonateDiagnostics.record('audio_focus_unduck', {
        'level': restored,
        'engine': _activeIsA ? 'A' : 'B',
      }));
    } catch (_) {
      _isDucked = false;
      try {
        await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
      } catch (_) {}
    }
  }

  /// Re-claim session then resume after a call / exclusive focus loss.
  Future<void> _resumeAfterSystemFocus() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
    // Brief settle for OEM audio policy after a call.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!_userWantsPlaying) return;
    _isDucked = false;
    try {
      await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
    } catch (_) {}
    await resumePlayback(source: 'system');
    // Nudge volume again — some devices stay muted one tick after setActive.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_userWantsPlaying && !_crossfadeInProgress) {
      try {
        await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
        if (!audioPlayer.playing) {
          try {
            audioPlayer.play();
          } catch (_) {}
        }
      } catch (_) {}
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
      await _loadResumeMap(prefs);
      if (ids.isEmpty || currentSong != null || _queue.isNotEmpty) return;
      final savedIndex = prefs.getInt(_savedQueueIndexKey) ?? 0;
      final songs = await _database.getAllSongs();
      await _visibility.load();
      final visibleSongs = _visibility.filter(songs, (song) => song.id);
      final byId = <String, Song>{for (final song in visibleSongs) song.id: song};
      final restored = ids.map((id) => byId[id]).whereType<Song>().toList();
      if (restored.isEmpty) return;
      _queue = restored;
      _queueIndex = savedIndex.clamp(0, restored.length - 1).toInt();
      currentSong = _queue[_queueIndex];
      currentDuration = currentSong!.duration;
      // Restore last known position for the current song (if any).
      if (_resumeSongId == currentSong!.id && _resumePositionMs > 1500) {
        final cap = currentDuration?.inMilliseconds ?? _resumePositionMs;
        final ms = _resumePositionMs.clamp(0, cap).toInt();
        // Don't resume at the very end — treat as finished.
        if (cap > 0 && ms >= cap - 2000) {
          currentPosition = Duration.zero;
          _resumePositionMs = 0;
        } else {
          currentPosition = Duration(milliseconds: ms);
        }
      } else {
        currentPosition = Duration.zero;
      }
      notifyListeners();
    } catch (e) { debugPrint('Playback queue restore failed: $e'); } finally { _queueRestoreInProgress = false; }
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isEmpty) { await prefs.remove(_savedQueueIdsKey); await prefs.remove(_savedQueueIndexKey); }
      else { await prefs.setStringList(_savedQueueIdsKey, _queue.map((song) => song.id).toList()); await prefs.setInt(_savedQueueIndexKey, _queueIndex); }
    } catch (e) { debugPrint('Playback queue persistence failed: $e'); }
  }

  void _publishServiceState({bool positionOnly = false}) {
    final handler = audioHandler;
    if (handler is! AudioServiceHandler) return;
    Duration pos = currentPosition;
    Duration? buffered;
    try { pos = audioPlayer.position; buffered = audioPlayer.bufferedPosition; } catch (_) { buffered = currentPosition; }
    if (positionOnly) {
      handler.publishPositionTick(playing: isPlaying, position: pos, bufferedPosition: buffered, speed: 1.0);
      return;
    }
    handler.publishPlayback(song: currentSong, playing: isPlaying, position: pos, duration: currentDuration ?? currentSong?.duration, speed: 1.0, bufferedPosition: buffered, playbackQueue: _queue, queueIndex: _queueIndex);
  }

  void _bindActivePlayerStreams() {
    _playerStateSubscription?.cancel(); _positionSubscription?.cancel(); _currentIndexSubscription?.cancel(); _durationSubscription?.cancel(); _volumeSubscription?.cancel();
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
            // Do not re-claim focus mid-crossfade — it can reset OEM volume/routing mid-ramp.
            if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
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
    _currentIndexSubscription?.cancel();
    _currentIndexSubscription = player.currentIndexStream.listen((index) {
      if (index == null || _crossfadeEnabled || _crossfadeInProgress) return;
      if (!_gaplessSourceActive || _transportInFlight) return;
      if (index < 0 || index >= _gaplessWindowIds.length) return;
      final songId = _gaplessWindowIds[index];
      final globalIndex = _queue.indexWhere((s) => s.id == songId);
      if (globalIndex < 0) return;
      if (globalIndex == _queueIndex && currentSong?.id == songId) return;
      _queueIndex = globalIndex;
      currentSong = _queue[globalIndex];
      currentDuration = currentSong?.duration ?? player.duration;
      currentPosition = player.position;
      isPlaying = player.playing || _userWantsPlaying;
      unawaited(_persistQueue());
      unawaited(_startHistoryEvent(currentSong!));
      _publishServiceState();
      notifyListeners();
      unawaited(ResonateDiagnostics.record('playback_gapless_index', {
        'localIndex': index,
        'queueIndex': globalIndex,
        'windowStart': _gaplessWindowStart,
        'songId': currentSong?.id,
      }));
    });

    _positionSubscription = player.positionStream.listen((position) {
      if (currentPosition != position) {
        currentPosition = position;
      _maybeRecoverSilentPlayback();
        if (_activeHistoryEvent != null) {
          _activeHistoryPositionMs = position.inMilliseconds;
          _persistResumePosition();
        }
        notifyListeners();
        _publishServiceState(positionOnly: true);
      }
      _maybeStartAutomaticCrossfade(position);
      _armEndOfTrackWatchdog();
    });
    _durationSubscription = player.durationStream.listen((duration) { if (duration != null && currentDuration != duration) { currentDuration = duration; notifyListeners(); _publishServiceState(); } });
    // App volume is sourced from Android STREAM_MUSIC. Do not mirror the player's
    // internal gain into _volume or it will overwrite the system-volume value.
  }

  /// Call from app lifecycle (paused/inactive/detached) so position survives process death.
  void onAppBackgrounded() {
    _persistResumePosition(force: true);
    unawaited(_persistQueue());
  }

  void _persistResumePosition({bool force = false}) {
    final song = currentSong;
    if (song == null) return;
    final now = DateTime.now();
    if (!force && _lastResumePersist != null && now.difference(_lastResumePersist!) < const Duration(seconds: 3)) return;
    _lastResumePersist = now;
    final raw = currentPosition.inMilliseconds > 0
        ? currentPosition.inMilliseconds
        : _activeHistoryPositionMs;
    final cap = currentDuration?.inMilliseconds ?? 0;
    final position = (cap > 0 ? raw.clamp(0, cap) : raw).toInt();
    if (!force && position < 1500) return;
    // Near end → treat as finished for this song.
    if (cap > 0 && position >= cap - 2000) {
      _resumeBySongId.remove(song.id);
      if (_resumeSongId == song.id) {
        _resumeSongId = null;
        _resumePositionMs = 0;
      }
      unawaited(_saveResumeMap());
      return;
    }
    _resumePositionMs = position;
    _resumeSongId = song.id;
    _resumeBySongId[song.id] = position;
    unawaited(SharedPreferences.getInstance().then((prefs) async {
      await prefs.setInt(_resumePositionKey, position);
      await prefs.setString(_resumeSongIdKey, song.id);
      await prefs.setString(_resumeMapKey, jsonEncode(_resumeBySongId));
    }).catchError((error) {
      debugPrint('Playback resume save failed: $error');
    }));
  }

  Future<void> _loadResumeMap(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(_resumeMapKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _resumeBySongId
        ..clear()
        ..addAll({
          for (final e in decoded.entries)
            if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt(),
        });
    } catch (e) {
      debugPrint('Resume map load failed: $e');
    }
  }

  Future<void> _saveResumeMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_resumeMapKey, jsonEncode(_resumeBySongId));
    } catch (_) {}
  }

  /// Position to resume a specific song, if known (per-song map or last resume).
  int? resumePositionFor(String songId) {
    final mapped = _resumeBySongId[songId];
    if (mapped != null && mapped > 1500) return mapped;
    if (_resumeSongId == songId && _resumePositionMs > 1500) return _resumePositionMs;
    return null;
  }

  void _maybeStartAutomaticCrossfade(Duration position) {
    if (!_crossfadeEnabled || !audioPlayer.playing) return;
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight) {
      return;
    }
    final duration = audioPlayer.duration ?? currentDuration;
    if (duration == null || duration <= Duration.zero) return;
    final remaining = duration - position;
    if (remaining <= Duration.zero) return;

    // Repeat-one seamless loop (dual-engine self-handoff).
    if (_repeatMode == PlaybackRepeatMode.one) {
      if (!canRepeatSelfHandoff) return;
      final armMs = (_crossfadeDurationMs + 2500).clamp(2500, 12000);
      final triggerMs = (_crossfadeDurationMs + 1500).clamp(2000, 10000);
      final song = currentSong;
      if (song == null) return;
      if (remaining <= Duration(milliseconds: armMs) &&
          remaining > Duration(milliseconds: triggerMs) &&
          !_repeatSelfHandoffArmed) {
        _repeatSelfHandoffArmed = true;
        _repeatSelfTargetSongId = song.id;
        unawaited(_preloadRepeatSelf(song));
      }
      if (remaining > Duration(milliseconds: triggerMs)) return;
      if (remaining < const Duration(milliseconds: 900)) return;
      _automaticCrossfadeInFlight = true;
      unawaited(_runRepeatSelfHandoff());
      return;
    }

    if (!canCrossfadeNext) return;

    final preloadMs = (_crossfadeDurationMs + 10000).clamp(10000, 28000);
    final fadeArmMs = _crossfadeDurationMs + 2000;
    if (remaining <= Duration(milliseconds: preloadMs) &&
        remaining > Duration(milliseconds: fadeArmMs)) {
      unawaited(_preloadNextForCrossfade());
    }

    final startMarginMs = (1200 + (_crossfadeDurationMs ~/ 10)).clamp(1500, 3000);
    final triggerMs = (_crossfadeDurationMs + startMarginMs).clamp(2000, 16000);
    if (remaining > Duration(milliseconds: triggerMs)) return;
    if (remaining < const Duration(milliseconds: 1200)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());
  }


  Future<void> _preloadRepeatSelf(Song song) async {
    if (_repeatSelfHandoffInFlight) return;
    final incoming = inactivePlayer;
    final incomingEq = inactiveEqualizer;
    final incomingLoud = inactiveLoudnessEnhancer;
    try {
      await ResonateDiagnostics.record('repeat_self_arm', {
        'songId': song.id,
        'positionMs': currentPosition.inMilliseconds,
        'xfMs': _crossfadeDurationMs,
      });
      try {
        await incoming.stop();
      } catch (_) {}
      await _loadSingle(incoming, incomingEq, incomingLoud, song, start: false);
      try {
        await incoming.seek(Duration.zero);
      } catch (_) {}
      try {
        await incoming.setVolume(0.0);
      } catch (_) {}
      _preloadedNextSongId = song.id;
    } catch (e) {
      debugPrint('repeat self preload failed: $e');
      _repeatSelfHandoffArmed = false;
      _repeatSelfTargetSongId = null;
      unawaited(ResonateDiagnostics.record('repeat_self_cancel', {
        'reason': 'preload_fail',
        'error': '$e',
      }));
    }
  }

  Future<void> _runRepeatSelfHandoff() async {
    final song = currentSong;
    final targetId = _repeatSelfTargetSongId ?? song?.id;
    if (song == null || targetId == null || song.id != targetId) {
      _automaticCrossfadeInFlight = false;
      _repeatSelfHandoffArmed = false;
      return;
    }
    final ok = await _performRepeatSelfHandoff(
      milliseconds: _crossfadeDurationMs,
      fadeType: _crossfadeFadeType,
    );
    _automaticCrossfadeInFlight = false;
    _repeatSelfHandoffArmed = false;
    _repeatSelfHandoffInFlight = false;
    _repeatSelfTargetSongId = null;
    if (!ok) {
      // Fallback: classic seek-to-start on the active engine.
      try {
        await audioPlayer.seek(Duration.zero);
        if (_userWantsPlaying) await audioPlayer.play();
      } catch (_) {}
      unawaited(ResonateDiagnostics.record('repeat_self_fallback', {
        'reason': 'handoff_failed',
        'songId': song.id,
      }));
    }
  }

  Future<bool> _performRepeatSelfHandoff({
    required int milliseconds,
    String fadeType = 'linear',
  }) async {
    final song = currentSong;
    if (song == null || song.filePath.trim().isEmpty) return false;
    if (!audioPlayer.playing && !_userWantsPlaying) return false;
    _repeatSelfHandoffInFlight = true;
    _crossfadeInProgress = true;
    final outgoing = audioPlayer;
    final incoming = inactivePlayer;
    final incomingEq = inactiveEqualizer;
    final incomingLoud = inactiveLoudnessEnhancer;
    final master = _eqPreampScale.clamp(0.05, 1.0);
    final ms = milliseconds.clamp(500, 12000);
    try {
      // No DJ stretch / SFX on self-loop — pure volume blend.
      try {
        await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      } catch (_) {}
      try {
        await outgoing.setLoopMode(LoopMode.off);
      } catch (_) {}

      final already = _preloadedNextSongId == song.id;
      if (!already) {
        try {
          await incoming.stop();
        } catch (_) {}
        await _loadSingle(incoming, incomingEq, incomingLoud, song, start: false);
      }
      try {
        await incoming.seek(Duration.zero);
      } catch (_) {}
      await incoming.setVolume(0.0);

      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}

      try {
        await incoming.play();
      } catch (_) {}

      unawaited(ResonateDiagnostics.record('repeat_self_ramp', {
        'songId': song.id,
        'fromEngine': _activeIsA ? 'A' : 'B',
        'toEngine': _activeIsA ? 'B' : 'A',
        'ms': ms,
      }));

      final steps = (ms / 40).round().clamp(8, 80);
      final stepMs = (ms / steps).round().clamp(20, 80);
      for (var i = 1; i <= steps; i++) {
        if (!_repeatSelfHandoffInFlight || !_userWantsPlaying) {
          // Cancelled mid-ramp.
          try {
            await incoming.pause();
          } catch (_) {}
          try {
            await incoming.setVolume(0.0);
          } catch (_) {}
          try {
            await outgoing.setVolume(master);
          } catch (_) {}
          return false;
        }
        final t = i / steps;
        double outV;
        double inV;
        switch (fadeType) {
          case 'ease_in':
            outV = master * (1.0 - t * t);
            inV = master * (t * t);
            break;
          case 'ease_out':
            final u = 1.0 - t;
            outV = master * (u * u);
            inV = master * (1.0 - u * u);
            break;
          case 'ease_in_out':
            final s = t * t * (3.0 - 2.0 * t);
            outV = master * (1.0 - s);
            inV = master * s;
            break;
          default:
            outV = master * (1.0 - t);
            inV = master * t;
        }
        try {
          await outgoing.setVolume(outV.clamp(0.0, 1.0));
        } catch (_) {}
        try {
          await incoming.setVolume(inV.clamp(0.0, 1.0));
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }

      // Commit: swap engines, same song + index.
      _activeIsA = !_activeIsA;
      _lastCompletionSongId = null;
      currentPosition = incoming.position;
      currentDuration = song.duration;
      isPlaying = incoming.playing || _userWantsPlaying;
      _bindActivePlayerStreams();
      _publishServiceState();
      notifyListeners();

      try {
        await outgoing.pause();
      } catch (_) {}
      try {
        await outgoing.setVolume(master);
      } catch (_) {}
      try {
        await incoming.setVolume(master);
      } catch (_) {}
      _preloadedNextSongId = null;

      await ResonateDiagnostics.record('repeat_self_committed', {
        'songId': song.id,
        'activeEngine': _activeIsA ? 'A' : 'B',
        'queueIndex': _queueIndex,
      });
      return true;
    } catch (e, st) {
      debugPrint('repeat self handoff failed: $e
$st');
      try {
        await incoming.pause();
      } catch (_) {}
      try {
        await outgoing.setVolume(master);
      } catch (_) {}
      return false;
    } finally {
      _crossfadeInProgress = false;
      _repeatSelfHandoffInFlight = false;
      _repeatSelfHandoffArmed = false;
      _repeatSelfTargetSongId = null;
    }
  }

  Future<void> _preloadNextForCrossfade() async {
    if (!_crossfadeEnabled || _crossfadePreloadInFlight || !canCrossfadeNext) return;
    final next = _crossfadeTargetSong;
    if (next == null) return;
    if (_preloadedNextSongId == next.id) return;
    _crossfadePreloadInFlight = true;
    // DJ Mode: priority-warm analysis for current + next queue head (not only idle scan).
    if (_djAnalysis != null &&
        (_djBeatAlignActive || _djTempoMatchActive)) {
      final cur = currentSong;
      if (cur != null) _djAnalysis!.scheduleAnalyze(cur);
      _djAnalysis!.scheduleAnalyze(next);
      // Warm a few upcoming rows so Autopilot/Intelligence handoffs stay ready.
      final start = _queueIndex + 1;
      final end = (start + 4).clamp(0, _queue.length);
      for (var i = start; i < end; i++) {
        if (i == _crossfadeTargetIndex) continue;
        _djAnalysis!.scheduleAnalyze(_queue[i]);
      }
    }
    // Snapshot outgoing level — never raise A/B while preloading.
    final outgoing = audioPlayer;
    double? outgoingVol;
    try {
      outgoingVol = outgoing.volume;
    } catch (_) {
      outgoingVol = _volume;
    }
    try {
      final incoming = inactivePlayer;
      final incomingEq = inactiveEqualizer;
      final incomingLoud = inactiveLoudnessEnhancer;
      await incoming.setLoopMode(LoopMode.off);
      try {
        await incoming.stop();
      } catch (_) {}
      await incoming.setVolume(0.0);
      await incoming.setAudioSource(AudioSource.uri(_audioUri(next.filePath), tag: next));
      unawaited(_enableEffects(incoming, incomingEq, incomingLoud));
      await incoming.setVolume(0.0);
      // Decode/warm without staying audible: brief play then pause at volume 0.
      try {
        incoming.play();
      } catch (_) {}
      for (var i = 0; i < 6 && !incoming.playing; i++) {
        await Future<void>.delayed(Duration(milliseconds: 30 + i * 15));
        try {
          await incoming.setVolume(0.0);
        } catch (_) {}
        if (i % 2 == 0) {
          try {
            incoming.play();
          } catch (_) {}
        }
      }
      try {
        await incoming.pause();
      } catch (_) {}
      try {
        await incoming.seek(Duration.zero);
      } catch (_) {}
      await incoming.setVolume(0.0);
      // Restore outgoing if anything touched the active engine (defensive).
      try {
        final targetOut = (outgoingVol ?? _volume).clamp(0.0, 1.0);
        if ((outgoing.volume - targetOut).abs() > 0.02) {
          await outgoing.setVolume(targetOut);
        }
      } catch (_) {}
      _preloadedNextSongId = next.id;
      await ResonateDiagnostics.record('crossfade_preloaded', {
        'songId': next.id,
        'queueIndex': _crossfadeTargetIndex,
        'playing': incoming.playing,
        'repeatMode': _repeatMode.name,
        'outgoingVolume': outgoingVol,
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
      final timeout = Duration(milliseconds: (_crossfadeDurationMs + 12000).clamp(12000, 30000));
      final ok = await _performTrueCrossfade(
        milliseconds: _crossfadeDurationMs,
        fadeType: _crossfadeFadeType,
        generation: generation,
      ).timeout(timeout, onTimeout: () {
        debugPrint('automatic crossfade timed out');
        return false;
      });
      if (ok) return;
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
      await ResonateDiagnostics.record('crossfade_fallback_soft', {
        'fromSongId': fromSongId,
        'queueIndex': fromIndex,
      });
      try {
        await inactivePlayer.stop();
      } catch (_) {}
      await _softFadeOutActive(milliseconds: 500);
      if (currentSong?.id != fromSongId || _queueIndex != fromIndex) return;
      final nextIdx = fromIndex < _queue.length - 1
          ? fromIndex + 1
          : (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty ? 0 : -1);
      if (nextIdx >= 0) {
        final next = _queue[nextIdx];
        final token = _playbackIntentGate.issue();
        await _playSongInternal(next, queue: _queue, startIndex: nextIdx, playbackIntentToken: token);
      }
    } catch (e) {
      debugPrint('automatic crossfade error: $e');
      if (currentSong?.id == fromSongId && _queueIndex == fromIndex) {
        try {
          await inactivePlayer.stop();
        } catch (_) {}
        try {
          await _softFadeOutActive(milliseconds: 400);
        } catch (_) {}
        final nextIdx = fromIndex < _queue.length - 1
            ? fromIndex + 1
            : (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty ? 0 : -1);
        if (nextIdx >= 0) {
          try {
            final next = _queue[nextIdx];
            final token = _playbackIntentGate.issue();
            await _playSongInternal(next, queue: _queue, startIndex: nextIdx, playbackIntentToken: token);
          } catch (_) {}
        }
      }
    } finally {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
    }
  }

  /// Short equal-power out-only ramp so fallback never hard-cuts an audible track.
  Future<void> _softFadeOutActive({int milliseconds = 500}) async {
    final player = audioPlayer;
    final steps = (milliseconds / 40).round().clamp(4, 40);
    double start = _eqPreampScale;
    try {
      start = player.volume.clamp(0.0, 1.0);
    } catch (_) {}
    if (start <= 0.02) {
      try {
        await player.pause();
      } catch (_) {}
      return;
    }
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final gain = math.cos(t * (math.pi / 2.0));
      try {
        await player.setVolume((start * gain).clamp(0.0, 1.0));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    try {
      await player.setVolume(0.0);
    } catch (_) {}
    try {
      await player.pause();
    } catch (_) {}
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
      final song = currentSong;
      if (song != null && _userWantsPlaying) {
        final token = _playbackIntentGate.issue();
        try {
          await _playSongInternal(
            song,
            queue: _queue,
            startIndex: _queueIndex,
            playbackIntentToken: token,
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _advanceAfterCompletion(String completedSongId) {
    if (_completionAdvanceInProgress) return Future<void>.value();
    // Already moved past this track — do not double-advance.
    if (currentSong != null &&
        currentSong!.id != completedSongId &&
        !_crossfadeInProgress &&
        !_automaticCrossfadeInFlight) {
      unawaited(ResonateDiagnostics.record('completion_advance_result', {
        'result': 'ignored_stale',
        'fromSongId': completedSongId,
        'currentSongId': currentSong?.id,
      }));
      return Future<void>.value();
    }
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
        // Dual-engine self-handoff owns the loop when crossfade is on.
        if (_repeatSelfHandoffInFlight ||
            _crossfadeInProgress ||
            (_crossfadeEnabled && _automaticCrossfadeInFlight)) {
          await ResonateDiagnostics.record('completion_advance_result', {
            'result': 'repeat_deferred_to_self_handoff',
            'songId': currentSong?.id,
          });
          return;
        }
        _lastCompletionSongId = null;
        currentPosition = Duration.zero;
        await audioPlayer.seek(Duration.zero);
        await audioPlayer.play();
        isPlaying = true;
        await _startHistoryEvent(currentSong!);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('completion_advance_result', {
          'result': 'repeated',
          'songId': currentSong?.id,
        });
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
    unawaited(Future<void>.delayed(const Duration(milliseconds: 500), () async {
      try {
        await _audioEffectsController.activateFor(player);
      } catch (e) {
        debugPrint('deferred enableEffects failed: $e');
      }
    }));
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

  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0, bool resumeIfPossible = false, int? resumeAtMs}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    _lastCompletionSongId = null;
    if (resumeAtMs != null && resumeAtMs > 1500) {
      _resumeSongId = song.id;
      _resumePositionMs = resumeAtMs;
      _resumeBySongId[song.id] = resumeAtMs;
    } else if (resumeIfPossible) {
      final mapped = resumePositionFor(song.id);
      if (mapped != null) {
        _resumeSongId = song.id;
        _resumePositionMs = mapped;
      }
    }
    final shouldResume = resumeIfPossible && _resumeSongId == song.id && _resumePositionMs > 1500;
    return _serializePlayback(
      () => _playSongInternal(song, queue: queue, startIndex: startIndex, resume: shouldResume, playbackIntentToken: intentToken),
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

    // Clear any leftover DJ stretch / muted-engine state before a normal play.
    try {
      await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
    } catch (_) {}

    // Phase 2: non-crossfade play always on Engine A (rebind if we were on B).
    _ensureEngineA(reason: 'play_song_internal');
    final target = _playerA;
    final targetEq = _equalizerA;
    final targetLoud = _loudnessA;
    final outgoing = null; // never hand off from B on the normal path

    _loadingSource = true;
    _userWantsPlaying = true;
    await _claimAudioFocus(reason: 'play_song_internal');

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
              final upcoming = <Song>[...normalized]..removeAt(selectedIndex)..shuffle(math.Random());
              return <Song>[selected, ...upcoming];
            }()
          : normalized;
      final nextIndex = _shuffleEnabled && normalized.length > 1 ? 0 : selectedIndex;

      // Pin UI to the song we intend to play before any native load races.
      currentSong = selectedSong;
      _queue = nextQueue;
      _queueIndex = nextIndex;
      currentDuration = selectedSong.duration;
      currentPosition = Duration.zero;
      notifyListeners();
      _publishServiceState();

      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (e) {
        debugPrint('AudioSession setActive (pre-source) failed: $e');
      }

      final loopMode = (!_crossfadeEnabled)
          ? switch (_repeatMode) {
              PlaybackRepeatMode.one => LoopMode.one,
              PlaybackRepeatMode.all => LoopMode.all,
              PlaybackRepeatMode.off => LoopMode.off,
            }
          : LoopMode.off;
      await timed('setLoopMode', target.setLoopMode(loopMode), ms: 2000);
      await step('set_source_start', {'path': selectedSong.filePath});

      Duration? durationFromSource;
      // Gapless: only a short window around the current track — never the entire
      // library (270+ content:// URIs caused Loading interrupted / stalled UI).
      const gaplessWindow = 12;
      final wantGapless = !_crossfadeEnabled && nextQueue.length > 1;
      _gaplessSourceActive = false;
      _gaplessWindowIds = const [];
      if (wantGapless) {
        try {
          final start = (nextIndex - 1).clamp(0, nextQueue.length - 1);
          final end = (nextIndex + gaplessWindow).clamp(0, nextQueue.length);
          final window = nextQueue.sublist(start, end)
              .where((s) => s.filePath.trim().isNotEmpty)
              .toList();
          final children = window
              .map((s) => AudioSource.uri(_audioUri(s.filePath), tag: s))
              .toList();
          final localIndex = window.indexWhere((s) => s.id == selectedSong.id);
          final safeLocal = localIndex >= 0 ? localIndex : 0;
          if (children.length > 1) {
            durationFromSource = await timedValue<Duration?>(
              'setAudioSource_gapless',
              target.setAudioSource(
                ConcatenatingAudioSource(children: children, useLazyPreparation: true),
                initialIndex: safeLocal,
                initialPosition: Duration.zero,
              ),
              ms: 15000,
            );
            _gaplessSourceActive = true;
            _gaplessWindowStart = start;
            _gaplessWindowIds = window.map((s) => s.id).toList();
            await ResonateDiagnostics.record('playback_gapless_source', {
              'children': children.length,
              'localIndex': safeLocal,
              'windowStart': start,
              'songId': selectedSong.id,
              'repeatMode': _repeatMode.name,
            });
          }
        } catch (e) {
          debugPrint('Gapless setAudioSource failed: $e');
          durationFromSource = null;
          _gaplessSourceActive = false;
          _gaplessWindowIds = const [];
        }
      }
      if (durationFromSource == null) {
        durationFromSource = await timedValue<Duration?>(
          'setAudioSource',
          target.setAudioSource(
            AudioSource.uri(_audioUri(selectedSong.filePath), tag: selectedSong),
          ),
          ms: 15000,
        );
      }
      await step('set_source_done', {
        'durationMs': durationFromSource?.inMilliseconds,
        'processingState': target.processingState.name,
        'gapless': wantGapless && durationFromSource != null,
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

      await timed('setVolume', target.setVolume(_eqPreampScale.clamp(0.05, 1.0)), ms: 2000);
      try { await target.setSpeed(1.0); } catch (_) {}

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
      // Phase 7: full listen after DJ handoff → soft positive signal.
      try {
        final handoffAt = _lastDjHandoffAt;
        final fromId = _lastDjFromId;
        final toId = _lastDjToId;
        final strategy = _lastDjStrategy;
        if (wasCompleted &&
            handoffAt != null &&
            fromId != null &&
            toId != null &&
            strategy != null &&
            event.songId == toId) {
          unawaited(DjTransitionMemory.recordOutcome(
            fromId: fromId,
            toId: toId,
            strategy: strategy,
            successful: true,
          ));
          unawaited(ResonateDiagnostics.recordDj(
            stage: 'learn',
            outcome: 'completed',
            reason: strategy,
            songId: toId,
            extra: {'fromId': fromId},
          ));
          _lastDjHandoffAt = null;
        }
      } catch (_) {}

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

  Future<bool> enqueueSongs(List<Song> songs) async { await _visibility.load(); final additions = songs.where((s) => _visibility.isVisible(s.id) && s.filePath.trim().isNotEmpty && !_queue.any((q) => q.id == s.id)).toList(); if (additions.isEmpty) return false; if (_shuffleEnabled && additions.length > 1) additions.shuffle(math.Random()); _queue.addAll(additions); await _persistQueue(); notifyListeners(); return true; }
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
    try {
      await player.setSpeed(1.0);
    } catch (_) {}
    await player.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song));
    unawaited(_enableEffects(player, eq, loud));
    await player.setVolume(start ? _eqPreampScale.clamp(0.05, 1.0) : 0.0);
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


  Future<void> _clearDjStretchSpeeds({
    AudioPlayer? outgoing,
    AudioPlayer? incoming,
  }) async {
    _djStretchSpeedOut = null;
    _djStretchSpeedIn = null;
    try {
      if (outgoing != null) await outgoing.setSpeed(1.0);
    } catch (_) {}
    try {
      if (incoming != null) await incoming.setSpeed(1.0);
    } catch (_) {}
  }


  /// Soft transition SFX: mild reverb glue, always restored after crossfade.
  Future<void> _engageDjTransitionSfx({double energyScore = 0.5}) async {
    if (!_djSfxActive) return;
    try {
      await _djSfxRack.engage(
        energyScore: energyScore,
        equalizerA: _equalizerA,
        equalizerB: _equalizerB,
      );
      _djSfxEngaged = true;
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'engage',
        'preset': _djSfxRack.presetName,
        'energyScore': energyScore,
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }

  Future<void> _tickDjClubFxSweep(double t) async {
    if (!_djSfxEngaged) return;
    await _djSfxRack.tick(
      t,
      equalizerA: _equalizerA,
      equalizerB: _equalizerB,
      energyScore: _lastDjEnergyScore,
    );
  }

  Future<void> _restoreDjTransitionSfx() async {
    if (!_djSfxEngaged && !_djSfxActive && !_djSfxRack.engaged) return;
    try {
      // Soft release gap so SFX bridges the two songs instead of cutting at t=1.
      for (final t in <double>[1.15, 1.30, 1.45, 1.60]) {
        try {
          await _djSfxRack.tick(
            t,
            equalizerA: _equalizerA,
            equalizerB: _equalizerB,
            energyScore: _lastDjEnergyScore,
          );
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
      final preset = _djSfxRack.presetName;
      await _djSfxRack.restore(
        equalizerA: _equalizerA,
        equalizerB: _equalizerB,
      );
      _djSfxEngaged = false;
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'restore',
        'preset': preset,
      });
    } catch (e) {
      _djSfxEngaged = false;
      debugPrint('DJ transition SFX restore: $e');
    }
  }

  /// Step 2–3: optional beat seek + tempo stretch for the incoming handoff.
  Future<void> _prepareDjHandoff({
    required AudioPlayer outgoing,
    required AudioPlayer incoming,
    required Song? outgoingSong,
    required Song incomingSong,
  }) async {
    _lastDjCrossfadeBiasMs = 0;
    if ((!_djBeatAlignActive && !_djTempoMatchActive) || _djAnalysis == null) {
      return;
    }
    if (outgoingSong == null) return;
    try {
      List<DjAnalysis> results;
      try {
        final aFuture = _djAnalysis!.analyzeSongCachedFirst(outgoingSong);
        final bFuture = _djAnalysis!.analyzeSongCachedFirst(incomingSong);
        results = await Future.wait<DjAnalysis>([aFuture, bFuture]).timeout(
          const Duration(milliseconds: 2200),
          onTimeout: () => const <DjAnalysis>[],
        );
      } catch (e) {
        await ResonateDiagnostics.recordDj(
          stage: 'handoff_prepare',
          outcome: 'failed',
          reason: 'analysis_wait: $e',
        );
        return;
      }
      if (results.length < 2) return;
      final analysisA = results[0];
      final analysisB = results[1];
      final outPos = outgoing.position.inMilliseconds;
      final outDur = outgoingSong.duration.inMilliseconds > 0
          ? outgoingSong.duration.inMilliseconds
          : analysisA.durationMs;
      final plan = await planDjTransitionLearned(
        analysisA: analysisA,
        analysisB: analysisB,
        tempoMatchActive: _djTempoMatchActive,
        beatAlignActive: _djBeatAlignActive,
        maxStretchPercent: _djMaxStretchPercent,
        fromSongId: outgoingSong.id,
        toSongId: incomingSong.id,
        outgoingPositionMs: outPos,
        outgoingDurationMs: outDur,
      );
      _lastDjCrossfadeBiasMs = plan.crossfadeBiasMs;
      _lastDjEnergyScore = plan.energyScore.isFinite
          ? plan.energyScore.clamp(0.0, 1.0).toDouble()
          : 0.5;

      if (plan.strategy == 'safe_fallback') {
        await ResonateDiagnostics.record('dj_handoff_safe_fallback', {
          'reason': plan.reason,
          'strategy': plan.strategy,
          'outgoingSongId': outgoingSong.id,
          'incomingSongId': incomingSong.id,
          ...plan.toDiagExtra(),
        });
        await ResonateDiagnostics.recordDj(
          stage: 'handoff',
          outcome: 'applied',
          reason: plan.reason,
          songId: incomingSong.id,
          extra: plan.toDiagExtra(),
        );
        return;
      }

      final bpmA = plan.bpmA;
      final bpmB = plan.bpmB;
      if (bpmA == null || bpmB == null || bpmA < 40 || bpmB < 40) {
        await ResonateDiagnostics.recordDj(
          stage: 'handoff',
          outcome: 'applied',
          reason: 'missing_bpm_after_plan',
          songId: incomingSong.id,
          extra: plan.toDiagExtra(),
        );
        return;
      }
      final stretch = plan.stretch;
      final effectiveBpmB = stretch?.effectiveBpm ?? bpmB;
      final beatOffsetB = analysisB.beatOffsetMs ?? 0;
      final beatOffsetA = analysisA.beatOffsetMs ?? 0;
      var beatApplied = false;
      var tempoApplied = false;

      if (plan.attemptBeatAlign) {
        final posMs = outgoing.position.inMilliseconds;
        final seek = plan.usePhraseGrid
            ? computePhraseAlignedSeekMs(
                bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
                beatOffsetMsA: beatOffsetA,
                bpmB: effectiveBpmB,
                beatOffsetMsB: beatOffsetB,
                outgoingPositionMs: posMs,
                beatsPerPhrase: plan.phraseBeats,
                maxRelativeDelta: stretch != null ? 0.18 : 0.055,
              )
            : computeBeatAlignedSeekMs(
                bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
                beatOffsetMsA: beatOffsetA,
                bpmB: effectiveBpmB,
                beatOffsetMsB: beatOffsetB,
                outgoingPositionMs: posMs,
                maxRelativeDelta: stretch != null ? 0.18 : 0.055,
              );
        if (seek == null) {
          await ResonateDiagnostics.recordDj(
            stage: 'beat_align',
            outcome: 'skipped',
            reason: 'bpm_delta',
            bpmA: bpmA,
            bpmB: bpmB,
            songId: incomingSong.id,
          );
        } else {
          final dur = incoming.duration ?? incomingSong.duration;
          var target = seek;
          if (dur > Duration.zero && target >= dur) {
            final periodMs = (60000.0 / effectiveBpmB).round();
            if (periodMs > 0) {
              target = Duration(milliseconds: target.inMilliseconds % periodMs);
            } else {
              target = Duration.zero;
            }
          }
          await incoming.seek(target);
          beatApplied = true;
          await ResonateDiagnostics.record('dj_beat_align_applied', {
            'outgoingSongId': outgoingSong.id,
            'incomingSongId': incomingSong.id,
            'bpmA': bpmA,
            'bpmB': bpmB,
            'seekMs': target.inMilliseconds,
            'outgoingPosMs': posMs,
            'stretched': stretch != null,
            'harmonicScore': plan.harmonicScore,
          });
        }
      }

      if (stretch != null) {
        try {
          if ((stretch.speedOutgoing - 1.0).abs() > 0.001) {
            await outgoing.setSpeed(stretch.speedOutgoing);
          }
          await incoming.setSpeed(stretch.speedIncoming);
          _djStretchSpeedOut = stretch.speedOutgoing;
          _djStretchSpeedIn = stretch.speedIncoming;
          tempoApplied = true;
          await ResonateDiagnostics.record('dj_tempo_match_applied', {
            'outgoingSongId': outgoingSong.id,
            'incomingSongId': incomingSong.id,
            'bpmA': bpmA,
            'bpmB': bpmB,
            'speedOut': stretch.speedOutgoing,
            'speedIn': stretch.speedIncoming,
            'mode': stretch.mode,
            'effectiveBpm': stretch.effectiveBpm,
            'harmonicScore': plan.harmonicScore,
          });
        } catch (e) {
          await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
          await ResonateDiagnostics.recordDj(
            stage: 'tempo_match',
            outcome: 'failed',
            reason: e.toString(),
            songId: incomingSong.id,
          );
        }
      }

      final appliedStrategy = tempoApplied && beatApplied
          ? 'beat_tempo'
          : (tempoApplied
              ? 'tempo_match'
              : (beatApplied ? 'beat_align' : 'safe_fallback'));
      await ResonateDiagnostics.recordDj(
        stage: 'handoff',
        outcome: 'applied',
        reason: appliedStrategy,
        songId: incomingSong.id,
        bpmA: bpmA,
        bpmB: bpmB,
        extra: {
          ...plan.toDiagExtra(),
          'strategyApplied': appliedStrategy,
          'beatApplied': beatApplied,
          'tempoApplied': tempoApplied,
        },
      );
      _lastDjHandoffAt = DateTime.now();
      _lastDjFromId = outgoingSong.id;
      _lastDjToId = incomingSong.id;
      _lastDjStrategy = appliedStrategy;
    } catch (e) {
      debugPrint('DJ handoff prepare skipped: $e');
      try {
        await ResonateDiagnostics.recordDj(
          stage: 'handoff_prepare',
          outcome: 'failed',
          reason: e.toString(),
        );
      } catch (_) {}
    }
  }

  Future<bool> _performTrueCrossfade({required int milliseconds, String fadeType = 'linear', required int generation, int? playbackIntentToken}) async {
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    if (!_playbackIntentGate.isCurrent(intentToken)) return false;
    if (!canCrossfadeNext || currentSong == null || !audioPlayer.playing) return false;
    final nextIndex = _crossfadeTargetIndex;
    final nextSong = _crossfadeTargetSong;
    if (nextSong == null || nextSong.filePath.trim().isEmpty) return false;
    _crossfadeInProgress = true; final outgoing = audioPlayer; final outgoingSong = currentSong; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _eqPreampScale.clamp(0.05, 1.0);
    try {
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
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
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      await _prepareDjHandoff(
        outgoing: outgoing,
        incoming: incoming,
        outgoingSong: outgoingSong,
        incomingSong: nextSong,
      );
      await _engageDjTransitionSfx(energyScore: _lastDjEnergyScore);
      // Fire-and-poll play on B — await play() can hang and block auto-next forever.
      try {
        incoming.play();
      } catch (_) {}
      var incomingStarted = incoming.playing;
      for (var i = 0; i < 25 && !incomingStarted; i++) {
        if (incoming.playing) {
          incomingStarted = true;
          break;
        }
        if (i == 5 || i == 12 || i == 18) {
          try { await incoming.seek(Duration.zero); } catch (_) {}
          try { incoming.play(); } catch (_) {}
        }
        await Future<void>.delayed(Duration(milliseconds: 40 + i * 15));
        incomingStarted = incoming.playing;
      }
      if (!incomingStarted) {
        _preloadedNextSongId = null;
        await ResonateDiagnostics.record('crossfade_incoming_start_failed', {
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
        });
        throw StateError('crossfade incoming engine failed to start');
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      try { if (!incoming.playing) incoming.play(); } catch (_) {}
      // Start from the *current* outgoing level — never boost to master mid-track
      // (that was the pre-crossfade "bump" on some files).
      double startOut = master;
      try {
        startOut = outgoing.volume.clamp(0.0, 1.0);
      } catch (_) {}
      if (startOut > master) startOut = master;
      // Cap base to master so we never fade from above user volume.
      final base = startOut <= 0.01 ? master : startOut;
      try {
        await outgoing.setVolume(base);
      } catch (_) {}
      await incoming.setVolume(0.0);

      final plannedMs = (milliseconds + _lastDjCrossfadeBiasMs).clamp(500, 12000).toInt();
      if (_lastDjCrossfadeBiasMs != 0) {
        unawaited(ResonateDiagnostics.record('crossfade_energy_bridge', {
          'biasMs': _lastDjCrossfadeBiasMs,
          'baseMs': milliseconds,
          'plannedMs': plannedMs,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
        }));
      }
      int remainingMs = plannedMs;
      try {
        final d = outgoing.duration;
        final p = outgoing.position;
        if (d != null && d > Duration.zero) {
          final rem = d.inMilliseconds - p.inMilliseconds;
          if (rem < 1200) {
            await ResonateDiagnostics.record('crossfade_aborted_too_late', {
              'remainingMs': rem,
              'plannedMs': plannedMs,
            });
            try { await incoming.stop(); } catch (_) {}
            try { await outgoing.setVolume(base); } catch (_) {}
            await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
            await _restoreDjTransitionSfx();
            return false;
          }
          remainingMs = (rem - 150).clamp(1200, plannedMs).toInt();
        }
      } catch (_) {}
      final total = remainingMs;
      final gentle = Platform.isAndroid;
      final stepMs = gentle ? 36 : 24;
      final fadeStartedAt = DateTime.now();
      var lastOut = base;
      while (true) {
        if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) {
          try { await incoming.stop(); } catch (_) {}
          try { await outgoing.setVolume(master); } catch (_) {}
          await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'fade',
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }
        final elapsed = DateTime.now().difference(fadeStartedAt).inMilliseconds;
        final linear = (elapsed / total).clamp(0.0, 1.0);
        final t = switch (fadeType) {
          'ease_in' => linear * linear,
          'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)),
          'ease_in_out' => linear < 0.5
              ? 2.0 * linear * linear
              : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0,
          _ => linear,
        };
        // Equal-power: cos out / sin in — smooth energy, no mid-fade dip.
        final angle = t * (math.pi / 2.0);
        final outGain = math.cos(angle);
        final inGain = math.sin(angle);
        final outVol = (base * outGain).clamp(0.0, 1.0);
        final inVol = (master * inGain).clamp(0.0, 1.0);
        lastOut = outVol;
        final stepStarted = DateTime.now();
        try {
          // Parallel volume writes so outgoing does not stall waiting on incoming.
          await Future.wait([
            outgoing.setVolume(outVol),
            incoming.setVolume(inVol),
          ]);
        } catch (_) {}
        // Club-style filter-sweep feel alongside the volume curve.
        if (_djSfxEngaged && (linear * 20).round() % 2 == 0) {
          unawaited(_tickDjClubFxSweep(linear));
        }
        if (linear >= 1.0) break;
        final spent = DateTime.now().difference(stepStarted).inMilliseconds;
        final sleep = (stepMs - spent).clamp(0, stepMs);
        if (sleep > 0) {
          await Future<void>.delayed(Duration(milliseconds: sleep));
        }
      }
      await _restoreDjTransitionSfx();
      // Guarantee silence on outgoing before pause/stop — never cut from a
      // still-audible level (the "sudden volume loss" symptom).
      for (var s = 0; s < 3; s++) {
        try { await outgoing.setVolume(0.0); } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 25));
        try {
          if (outgoing.volume <= 0.02) break;
        } catch (_) {
          break;
        }
      }
      if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(base); } catch (_) {} await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'commit', 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
      // Finish the outgoing history record while currentSong still refers to it.
      // Mutating currentSong first caused history to be attributed to the next track.
      await _finishHistoryEvent();
      if (!_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} return false; }
      // Pause only after volume is already 0 so pause cannot audibly chop the tail.
      try { await outgoing.pause(); } catch (_) {}
      try { await incoming.setLoopMode(LoopMode.off); } catch (_) {}
      try { await incoming.setVolume(master); } catch (_) {}
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      try {
        if (incoming.volume < 0.05) await incoming.setVolume(master);
      } catch (_) {}
      // Hard guarantee: incoming must be audible before we flip active engine.
      try {
        await incoming.setSpeed(1.0);
        await incoming.setVolume(master);
        if (!incoming.playing) {
          try { incoming.play(); } catch (_) {}
        }
        await ResonateDiagnostics.record('crossfade_commit_volume', {
          'volume': incoming.volume,
          'playing': incoming.playing,
          'master': master,
          'songId': nextSong.id,
        });
      } catch (_) {}
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active
      _queueIndex = nextIndex; currentSong = nextSong; _lastCompletionSongId = null; currentDuration = nextSong.duration; currentPosition = incoming.position; isPlaying = incoming.playing;
      await _persistQueue(); _bindActivePlayerStreams(); await _startHistoryEvent(nextSong); _publishServiceState(); notifyListeners();
      try { await outgoing.stop(); } catch (_) {}
      // Restore volume on the now-idle engine so the next time it is used it is not stuck at 0.
      try { await outgoing.setVolume(master); } catch (_) {}
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
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      debugPrint('True crossfade failed: $e'); debugPrint('$stack');
      try { await incoming.stop(); } catch (_) {}
      try { await outgoing.setSpeed(1.0); } catch (_) {}
      try { await incoming.setSpeed(1.0); } catch (_) {}
      try { await outgoing.setVolume(master); } catch (_) {}
      try {
        if (outgoing.playing && outgoing.volume < 0.02) {
          await outgoing.setVolume(master);
        }
      } catch (_) {}
      await ResonateDiagnostics.record('crossfade_failed', {'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'error': e.toString(), 'intentToken': intentToken});
      try {
        await ResonateDiagnostics.recordDj(
          stage: 'crossfade',
          outcome: 'failed',
          reason: e.toString(),
          songId: nextSong.id,
        );
      } catch (_) {}
      if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) return false;
      try { await outgoing.stop(); await _playSongInternal(nextSong, queue: _queue, startIndex: nextIndex, playbackIntentToken: intentToken); return true; } catch (fallbackError) { debugPrint('Crossfade fallback failed: $fallbackError'); await ResonateDiagnostics.record('crossfade_fallback_failed', {'incomingSongId': nextSong.id, 'error': fallbackError.toString(), 'intentToken': intentToken}); return false; }
    } finally {
      _crossfadeInProgress = false;
      // Always clear stretch + SFX even when the try path returned early.
      try {
        await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
      } catch (_) {}
      try {
        await _restoreDjTransitionSfx();
      } catch (_) {}
      // If UI thinks we are playing but active engine is near-silent, unstick.
      try {
        final active = audioPlayer;
        final vol = _eqPreampScale.clamp(0.05, 1.0).toDouble();
        if ((_userWantsPlaying || active.playing) && active.volume < 0.05) {
          await active.setSpeed(1.0);
          await active.setVolume(vol);
          await ResonateDiagnostics.record('playback_volume_unstick', {
            'reason': 'crossfade_finally',
            'volume': active.volume,
            'engine': _activeIsA ? 'A' : 'B',
          });
        }
      } catch (_) {}
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
    if (_repeatSelfHandoffArmed || _repeatSelfHandoffInFlight) {
      unawaited(ResonateDiagnostics.record('repeat_self_cancel', {
        'reason': 'transport_cancel',
        'songId': _repeatSelfTargetSongId,
      }));
    }
    _repeatSelfHandoffArmed = false;
    _repeatSelfHandoffInFlight = false;
    _repeatSelfTargetSongId = null;
    // Keep gapless window; transport may seek inside it.
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
        _isDucked = false;
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
          final midTransition =
              _crossfadeInProgress || _automaticCrossfadeInFlight;
          final target = _eqPreampScale.clamp(0.0, 1.0);
          // Start quiet then fade in (skip mid-crossfade — ramp owns volume).
          if (!midTransition) {
            try {
              await audioPlayer.setVolume(0.0);
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
          if (!midTransition && audioPlayer.playing) {
            await _fadePlayerVolume(
              audioPlayer,
              0.0,
              target,
              durationMs: source == 'system' ? 160 : _transportFadeMs,
            );
          } else if (!midTransition) {
            try {
              await audioPlayer.setVolume(target);
            } catch (_) {}
          }
          isPlaying = audioPlayer.playing || _userWantsPlaying;
          _publishServiceState();
          notifyListeners();
          unawaited(ResonateDiagnostics.record('playback_resume_fade', {
            'source': source,
            'faded': !midTransition,
            'playing': audioPlayer.playing,
          }));
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
    }, command: 'play', source: source, userInitiated: source != 'system', intentToken: intentToken);
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
    // System audio-focus pause must preserve intent so we can resume when focus returns.
    final fromSystemFocus = source == 'system';
    final fromNoisy = source == 'becoming_noisy';
    if (!fromSystemFocus) {
      _cancelAutomaticPlaybackWork();
    }
    return _serializePlayback(() async {
      try {
        if (!fromSystemFocus) {
          _userWantsPlaying = false;
        }
        final midTransition =
            _crossfadeInProgress || _automaticCrossfadeInFlight;
        // Soft fade-out for user (and short system) pause — skip mid-crossfade.
        if (!midTransition && audioPlayer.playing) {
          final from = audioPlayer.volume;
          final fadeMs = fromSystemFocus ? 120 : _transportFadeMs;
          await _fadePlayerVolume(audioPlayer, from, 0.0, durationMs: fadeMs);
        }
        await audioPlayer.pause();
        try {
          await inactivePlayer.pause();
        } catch (_) {}
        // Restore internal gain so the next play/resume fade-in starts clean.
        if (!midTransition) {
          try {
            await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
          } catch (_) {}
        }
        isPlaying = false;
        _isDucked = false;
        _persistResumePosition(force: true);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('audio_focus_pause', {
          'source': source,
          'userWantsPlaying': _userWantsPlaying,
          'preservedIntent': fromSystemFocus,
          'faded': !midTransition,
          'noisy': fromNoisy,
        });
      } catch (_) {}
    }, command: 'pause', source: source, userInitiated: !fromSystemFocus, intentToken: intentToken);
  }

  Future<void> stop({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      if (!_playbackIntentGate.isCurrent(intentToken)) return;
      _userWantsPlaying = false;
      await _finishHistoryEvent();
      await _stopBoth();
      isPlaying = false;
      currentPosition = Duration.zero;
      // Abandon audio focus so other apps can play without mixing with us.
      try {
        final session = await AudioSession.instance;
        await session.setActive(false);
      } catch (e) {
        debugPrint('AudioSession setActive(false) on stop failed: $e');
      }
      _publishServiceState();
      notifyListeners();
      await ResonateDiagnostics.record('audio_focus_stop', {'source': source});
    }, command: 'stop', source: source, userInitiated: true, intentToken: intentToken);
  }


  /// If the target queue index is already inside the active gapless window,
  /// seek to that local index instead of rebuilding ConcatenatingAudioSource.
  Future<bool> _tryGaplessSeekToQueueIndex(int queueIndex) async {
    if (!_gaplessSourceActive || _crossfadeEnabled) return false;
    if (queueIndex < 0 || queueIndex >= _queue.length) return false;
    final song = _queue[queueIndex];
    final local = _gaplessWindowIds.indexOf(song.id);
    if (local < 0) return false;
    try {
      await audioPlayer.seek(Duration.zero, index: local);
      _queueIndex = queueIndex;
      currentSong = song;
      currentDuration = song.duration ?? audioPlayer.duration;
      currentPosition = Duration.zero;
      isPlaying = true;
      _userWantsPlaying = true;
      try {
        audioPlayer.play();
      } catch (_) {}
      _publishServiceState();
      notifyListeners();
      await ResonateDiagnostics.record('playback_gapless_seek', {
        'localIndex': local,
        'queueIndex': queueIndex,
        'songId': song.id,
      });
      return true;
    } catch (e) {
      debugPrint('Gapless seek failed: $e');
      return false;
    }
  }

  int _pendingNextSteps = 0;

  Future<void> nextSong({String source = 'normal_player'}) {
    if (_transportInFlight || _loadingSource || _crossfadeInProgress) {
      _pendingNextSteps = (_pendingNextSteps + 1).clamp(0, 12);
      return Future<void>.value();
    }
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();

    return _serializePlayback(
      () async {
        if (_queue.isEmpty) return;
        final extra = _pendingNextSteps;
        _pendingNextSteps = 0;
        final steps = 1 + extra;
        // Phase 7: early skip after a DJ handoff → soft negative signal.
        try {
          final handoffAt = _lastDjHandoffAt;
          final fromId = _lastDjFromId;
          final toId = _lastDjToId;
          final strategy = _lastDjStrategy;
          if (handoffAt != null &&
              fromId != null &&
              toId != null &&
              strategy != null &&
              currentSong?.id == toId) {
            final age = DateTime.now().difference(handoffAt);
            final posMs = currentPosition.inMilliseconds;
            final durMs = (currentDuration ?? currentSong?.duration)?.inMilliseconds ?? 0;
            final earlyByTime = age < const Duration(seconds: 120) && posMs < 45000;
            final earlyByRatio =
                durMs > 0 && posMs < (durMs * 0.35).round() && age < const Duration(minutes: 3);
            if (earlyByTime || earlyByRatio) {
              // Heavier penalty the earlier the skip (deeper transition memory).
              final weight = posMs < 5000
                  ? 4
                  : posMs < 15000
                      ? 3
                      : posMs < 30000
                          ? 2
                          : 1;
              unawaited(DjTransitionMemory.recordOutcome(
                fromId: fromId,
                toId: toId,
                strategy: strategy,
                successful: false,
                weight: weight,
              ));
              unawaited(ResonateDiagnostics.recordDj(
                stage: 'learn',
                outcome: 'early_skip',
                reason: strategy,
                songId: toId,
                extra: {
                  'fromId': fromId,
                  'positionMs': posMs,
                  'weight': weight,
                  'ageMs': age.inMilliseconds,
                },
              ));
              _lastDjHandoffAt = null;
            }
          }
        } catch (_) {}
        _transportInFlight = true;
        try {
          var stepsLeft = steps.clamp(1, 12);
          while (stepsLeft > 0) {
            stepsLeft--;
            if (_queue.isEmpty) break;
            if (_queueIndex >= _queue.length - 1) {
              if (_repeatMode == PlaybackRepeatMode.all) {
                await _playSongInternal(_queue.first, queue: _queue, startIndex: 0, playbackIntentToken: intentToken);
              } else if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
                await _playSongInternal(currentSong!, queue: _queue, startIndex: _queueIndex, playbackIntentToken: intentToken);
              }
              break;
            }
            final nextIndex = _queueIndex + 1;
            if (await _tryGaplessSeekToQueueIndex(nextIndex)) {
              if (_pendingNextSteps > 0 && stepsLeft == 0) {
                stepsLeft = _pendingNextSteps.clamp(0, 12);
                _pendingNextSteps = 0;
              }
              continue;
            }
            await _playSongInternal(
              _queue[nextIndex],
              queue: _queue,
              startIndex: nextIndex,
              playbackIntentToken: intentToken,
            );
            if (_pendingNextSteps > 0 && stepsLeft == 0) {
              stepsLeft = _pendingNextSteps.clamp(0, 12);
              _pendingNextSteps = 0;
            }
          }
        } finally {
          _transportInFlight = false;
          if (_pendingNextSteps > 0) {
            final again = _pendingNextSteps;
            _pendingNextSteps = 0;
            unawaited(Future<void>.delayed(const Duration(milliseconds: 40), () {
              for (var i = 0; i < again; i++) {
                unawaited(nextSong(source: source));
              }
            }));
          }
        }
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
        _transportInFlight = true;
        try {
          if (_queueIndex > 0) {
            final previousIndex = _queueIndex - 1;
            if (await _tryGaplessSeekToQueueIndex(previousIndex)) return;
            await _playSongInternal(
              _queue[previousIndex],
              queue: _queue,
              startIndex: previousIndex,
              playbackIntentToken: intentToken,
            );
          } else {
            await audioPlayer.seek(Duration.zero);
            currentPosition = Duration.zero;
            if (_activeHistoryEvent != null) _activeHistoryPositionMs = 0;
            _persistResumePosition(force: true);
            notifyListeners();
            _publishServiceState();
          }
        } finally {
          _transportInFlight = false;
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
          final fromMs = currentPosition.inMilliseconds;
          final safe = Duration(
            milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds).toInt(),
          );
          await audioPlayer.seek(safe);
          currentPosition = safe;
          if (_activeHistoryEvent != null) {
            _activeHistoryPositionMs = safe.inMilliseconds;
          }
          // Local seek/replay evidence for Intelligence ranking (no audio content).
          final songId = currentSong?.id;
          if (songId != null && (fromMs - safe.inMilliseconds).abs() > 2500) {
            unawaited(IntelligenceSeekMemory().record(
              songId: songId,
              fromMs: fromMs,
              toMs: safe.inMilliseconds,
            ));
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
      // Keep EQ preamp digital attenuation; system volume is separate.
      if (!_crossfadeInProgress) {
        await audioPlayer.setVolume(_eqPreampScale);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Called by EqualizerProvider for preamp (−6 dB → ~0.5 scale, 0 dB → 1.0).
  Future<void> setEqPreampScale(double scale) async {
    _eqPreampScale = scale.clamp(0.25, 1.0);
    if (_crossfadeInProgress) {
      notifyListeners();
      return;
    }
    try {
      await audioPlayer.setVolume(_eqPreampScale);
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
    _sessionASub?.cancel();
    _sessionBSub?.cancel();
    _playerA.dispose();
    _playerB.dispose();
    super.dispose();
  }
}
