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
import '../dj_engine/dj_engine.dart';
import '../dj_engine/core/dj_policy.dart';
import '../dj_engine/intelligence/dj_autopilot_planner.dart';
import '../services/playback_authority.dart';
import '../services/playback_intent_gate.dart';
import '../services/resonate_diagnostics.dart';
import '../services/library_visibility_store.dart';
import '../services/audio_effects_bridge.dart';
import '../services/dj_sfx_rack.dart';
import '../services/audio_effects_controller.dart';
import '../services/loudness_service.dart';
import '../services/playback_coordinator.dart';
import '../playback/queue_store.dart';
import '../playback/resume_position_store.dart';
import '../playback/audio_focus_settings.dart';
import '../playback/crossfade_runtime.dart';
import '../playback/transport_epoch.dart';
import '../playback/engine_pair.dart';
import '../playback/dj_handoff_state.dart';
import '../playback/audio_leveling_settings.dart';
import '../playback/focus_interruption_runtime.dart';
import '../playback/playback_history_session.dart';
import '../playback/gapless_window_state.dart';
import '../playback/mode_playback_policy_state.dart';
import '../modes/services/audiobook_session_bridge.dart';
import '../modes/providers/mode_provider.dart';
import '../modes/services/podcast_session_bridge.dart';

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
  final PodcastSessionBridge _podcastSession = PodcastSessionBridge();
  final AudiobookSessionBridge _audiobookSession = AudiobookSessionBridge();
  ModeProvider? _modes;
  late final AudioEffectsController _audioEffectsController;
  final LibraryVisibilityStore _visibility = LibraryVisibilityStore.instance;
  final EnginePair _engines = EnginePair();
  /// Compatibility aliases — dual engines live in [_engines].
  AudioPlayer get _playerA => _engines.playerA;
  AudioPlayer get _playerB => _engines.playerB;
  AndroidEqualizer get _equalizerA => _engines.equalizerA;
  AndroidEqualizer get _equalizerB => _engines.equalizerB;
  AndroidLoudnessEnhancer get _loudnessA => _engines.loudnessA;
  AndroidLoudnessEnhancer get _loudnessB => _engines.loudnessB;
  bool get _activeIsA => _engines.activeIsA;
  set _activeIsA(bool value) => _engines.activeIsA = value;
  AudioPlayer get audioPlayer => _engines.active;
  AudioPlayer get inactivePlayer => _engines.inactive;
  AndroidEqualizer get equalizer => _engines.equalizer;
  AndroidLoudnessEnhancer get loudnessEnhancer => _engines.loudnessEnhancer;
  AndroidEqualizer get inactiveEqualizer => _engines.inactiveEqualizer;
  AndroidLoudnessEnhancer get inactiveLoudnessEnhancer =>
      _engines.inactiveLoudnessEnhancer;

  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration? currentDuration;
  double _volume = 1.0;
  /// User-selected EQ preamp, kept separate from the track leveling trim.
  double _eqPreampUserScale = 1.0;
  /// Effective preamp scale (user preamp multiplied by conservative track trim).
  /// Existing recovery, ducking and crossfade paths all consume this value.
  double _eqPreampScale = 1.0;
  final AudioLevelingSettings _levelingSettings = AudioLevelingSettings();
  /// Compatibility aliases — leveling prefs live in [_levelingSettings].
  bool get _audioLevelingEnabled => _levelingSettings.enabled;
  set _audioLevelingEnabled(bool value) => _levelingSettings.enabled = value;
  double get _audioLevelingTargetRmsDbfs => _levelingSettings.targetRmsDbfs;
  set _audioLevelingTargetRmsDbfs(double value) =>
      _levelingSettings.targetRmsDbfs = value;
  double _trackLevelingScale = 1.0;
  int _trackLevelingGeneration = 0;
  final LoudnessService _loudnessService = LoudnessService();
  /// Sleep-timer fade multiplier (1.0 = full, 0.0 = silent). Applied on top of preamp.
  double _sleepFadeScale = 1.0;
  /// Optional listener for Android audio session (Resonate native DSP).
  void Function(int sessionId)? onAndroidSession;
  StreamSubscription<int?>? _sessionASub;
  StreamSubscription<int?>? _sessionBSub;
  final QueueStore _queueStore = QueueStore();
  /// Compatibility aliases — queue state lives in [_queueStore].
  List<Song> get _queue => _queueStore.songs;
  set _queue(List<Song> value) =>
      _queueStore.replace(value, index: _queueStore.index);
  int get _queueIndex => _queueStore.index;
  set _queueIndex(int value) => _queueStore.index = value;
  bool get _shuffleEnabled => _queueStore.shuffleEnabled;
  set _shuffleEnabled(bool value) => _queueStore.shuffleEnabled = value;
  /// Compatibility aliases — mode policy runtime lives in [ModePlaybackPolicyState].
  final ModePlaybackPolicyState _modePlaybackPolicy = ModePlaybackPolicyState();
  bool get _modeCrossfadeAllowed => _modePlaybackPolicy.crossfadeAllowed;
  bool get _modeShuffleAllowed => _modePlaybackPolicy.shuffleAllowed;
  bool get _modePreciseResume => _modePlaybackPolicy.preciseResume;

  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;
  final CrossfadeRuntime _crossfadeRuntime = CrossfadeRuntime();
  /// Compatibility aliases — in-flight crossfade state lives in [_crossfadeRuntime].
  bool get _crossfadeInProgress => _crossfadeRuntime.inProgress;
  set _crossfadeInProgress(bool value) => _crossfadeRuntime.inProgress = value;
  bool get _completionAdvanceInProgress =>
      _crossfadeRuntime.completionAdvanceInProgress;
  set _completionAdvanceInProgress(bool value) =>
      _crossfadeRuntime.completionAdvanceInProgress = value;
  bool get _completionObservedDuringCrossfade =>
      _crossfadeRuntime.completionObservedDuringCrossfade;
  set _completionObservedDuringCrossfade(bool value) =>
      _crossfadeRuntime.completionObservedDuringCrossfade = value;
  String? get _completionObservedSongId =>
      _crossfadeRuntime.completionObservedSongId;
  set _completionObservedSongId(String? value) =>
      _crossfadeRuntime.completionObservedSongId = value;
  bool get _queueRestoreInProgress => _queueStore.restoreInProgress;
  set _queueRestoreInProgress(bool value) => _queueStore.restoreInProgress = value;
  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 3000;
  String _crossfadeFadeType = 'linear';
  bool get _automaticCrossfadeInFlight => _crossfadeRuntime.automaticInFlight;
  set _automaticCrossfadeInFlight(bool value) =>
      _crossfadeRuntime.automaticInFlight = value;
  /// Monotonic identity for the currently-owned automatic A/B transition.
  int get _automaticTransitionGeneration =>
      _crossfadeRuntime.automaticTransitionGeneration;
  set _automaticTransitionGeneration(int value) =>
      _crossfadeRuntime.automaticTransitionGeneration = value;
  final TransportEpoch _transportEpoch = TransportEpoch();
  /// Compatibility aliases — transport authority lives in [_transportEpoch].
  /// Bumped on every user transport (play/next/prev/pause). Automatic
  /// crossfade captures this and aborts if it changes mid-flight.
  int get _userTransportEpoch => _transportEpoch.epoch;
  set _userTransportEpoch(int value) => _transportEpoch.epoch = value;
  String? get _preloadedNextSongId => _crossfadeRuntime.preloadedNextSongId;
  set _preloadedNextSongId(String? value) =>
      _crossfadeRuntime.preloadedNextSongId = value;
  bool get _crossfadePreloadInFlight => _crossfadeRuntime.preloadInFlight;
  set _crossfadePreloadInFlight(bool value) =>
      _crossfadeRuntime.preloadInFlight = value;
  bool get _repeatSelfHandoffArmed => _crossfadeRuntime.repeatSelfHandoffArmed;
  set _repeatSelfHandoffArmed(bool value) =>
      _crossfadeRuntime.repeatSelfHandoffArmed = value;
  bool get _repeatSelfHandoffInFlight =>
      _crossfadeRuntime.repeatSelfHandoffInFlight;
  set _repeatSelfHandoffInFlight(bool value) =>
      _crossfadeRuntime.repeatSelfHandoffInFlight = value;
  int get _repeatSelfGeneration => _crossfadeRuntime.repeatSelfGeneration;
  set _repeatSelfGeneration(int value) =>
      _crossfadeRuntime.repeatSelfGeneration = value;
  int _modeBoundaryGeneration = 0;
  String? get _repeatSelfTargetSongId =>
      _crossfadeRuntime.repeatSelfTargetSongId;
  set _repeatSelfTargetSongId(String? value) =>
      _crossfadeRuntime.repeatSelfTargetSongId = value;
  /// DJ Mode Step 2 — feature flags + last handoff snapshot in [DjHandoffState].
  final DjHandoffState _djHandoff = DjHandoffState();
  bool get _djBeatAlignActive => _djHandoff.beatAlignActive;
  set _djBeatAlignActive(bool value) => _djHandoff.beatAlignActive = value;
  bool get _djTempoMatchActive => _djHandoff.tempoMatchActive;
  set _djTempoMatchActive(bool value) => _djHandoff.tempoMatchActive = value;
  int get _djMaxStretchPercent => _djHandoff.maxStretchPercent;
  set _djMaxStretchPercent(int value) => _djHandoff.maxStretchPercent = value;
  bool get _djSfxActive => _djHandoff.sfxActive;
  set _djSfxActive(bool value) => _djHandoff.sfxActive = value;
  DjPolicy get _djPolicy => _djHandoff.policy;
  set _djPolicy(DjPolicy value) => _djHandoff.policy = value;
  bool get _djSfxEngaged => _djHandoff.sfxEngaged;
  set _djSfxEngaged(bool value) => _djHandoff.sfxEngaged = value;
  final DjSfxRack _djSfxRack = DjSfxRack();
  DjAnalysisService? _djAnalysis;
  final DjEngine _djEngine = const DjEngine();
  final DjAutopilotPlanner _djAutopilotPlanner = const DjAutopilotPlanner();
  DjExecutionPlan? _activeDjExecutionPlan;
  double? get _djStretchSpeedOut => _djHandoff.stretchSpeedOut;
  set _djStretchSpeedOut(double? value) => _djHandoff.stretchSpeedOut = value;
  double? get _djStretchSpeedIn => _djHandoff.stretchSpeedIn;
  set _djStretchSpeedIn(double? value) => _djHandoff.stretchSpeedIn = value;
  DateTime? get _lastDjHandoffAt => _djHandoff.lastHandoffAt;
  set _lastDjHandoffAt(DateTime? value) => _djHandoff.lastHandoffAt = value;
  String? get _lastDjFromId => _djHandoff.lastFromId;
  set _lastDjFromId(String? value) => _djHandoff.lastFromId = value;
  String? get _lastDjToId => _djHandoff.lastToId;
  set _lastDjToId(String? value) => _djHandoff.lastToId = value;
  String? get _lastDjStrategy => _djHandoff.lastStrategy;
  set _lastDjStrategy(String? value) => _djHandoff.lastStrategy = value;
  double? get _lastDjTransitionScore => _djHandoff.lastTransitionScore;
  set _lastDjTransitionScore(double? value) =>
      _djHandoff.lastTransitionScore = value;
  double? get _lastDjTransitionConfidence => _djHandoff.lastTransitionConfidence;
  set _lastDjTransitionConfidence(double? value) =>
      _djHandoff.lastTransitionConfidence = value;
  List<String> get _lastDjTransitionRisks => _djHandoff.lastTransitionRisks;
  set _lastDjTransitionRisks(List<String> value) =>
      _djHandoff.lastTransitionRisks = value;
  int? get _lastDjTransitionDurationMs => _djHandoff.lastTransitionDurationMs;
  set _lastDjTransitionDurationMs(int? value) =>
      _djHandoff.lastTransitionDurationMs = value;
  int get _lastDjRecoveryAttempts => _djHandoff.lastRecoveryAttempts;
  set _lastDjRecoveryAttempts(int value) =>
      _djHandoff.lastRecoveryAttempts = value;
  int get _lastDjCrossfadeBiasMs => _djHandoff.lastCrossfadeBiasMs;
  set _lastDjCrossfadeBiasMs(int value) =>
      _djHandoff.lastCrossfadeBiasMs = value;
  double get _lastDjEnergyScore => _djHandoff.lastEnergyScore;
  set _lastDjEnergyScore(double value) => _djHandoff.lastEnergyScore = value;
  bool get _lastDjBassDuckNeeded => _djHandoff.lastBassDuckNeeded;
  set _lastDjBassDuckNeeded(bool value) =>
      _djHandoff.lastBassDuckNeeded = value;
  List<int> get _lastDjIncomingBeatMs => _djHandoff.lastIncomingBeatMs;
  set _lastDjIncomingBeatMs(List<int> value) =>
      _djHandoff.lastIncomingBeatMs = value;
  double? get _lastDjIncomingBpm => _djHandoff.lastIncomingBpm;
  set _lastDjIncomingBpm(double? value) => _djHandoff.lastIncomingBpm = value;
  int get _djBeatCorrectionAttempts => _djHandoff.beatCorrectionAttempts;
  set _djBeatCorrectionAttempts(int value) =>
      _djHandoff.beatCorrectionAttempts = value;
  double get _djRuntimeCorrectionBaseSpeed =>
      _djHandoff.runtimeCorrectionBaseSpeed;
  set _djRuntimeCorrectionBaseSpeed(double value) =>
      _djHandoff.runtimeCorrectionBaseSpeed = value;
  DateTime? get _djRuntimeCorrectionUntil => _djHandoff.runtimeCorrectionUntil;
  set _djRuntimeCorrectionUntil(DateTime? value) =>
      _djHandoff.runtimeCorrectionUntil = value;
  final DjBeatDriftCorrector _djBeatDriftCorrector = const DjBeatDriftCorrector();

  int? _androidSdkInt;
  final GaplessWindowState _gaplessWindow = GaplessWindowState();
  bool get _transportInFlight => _transportEpoch.inFlight;
  set _transportInFlight(bool value) => _transportEpoch.inFlight = value;
  int get _pendingUserTransportCount => _transportEpoch.pendingCount;
  set _pendingUserTransportCount(int value) =>
      _transportEpoch.pendingCount = value;
  bool get _userTransportPending => _transportEpoch.isPending;
  bool get _userWantsPlaying => _transportEpoch.userWantsPlaying;
  set _userWantsPlaying(bool value) =>
      _transportEpoch.userWantsPlaying = value;
  bool get _loadingSource => _transportEpoch.loadingSource;
  set _loadingSource(bool value) => _transportEpoch.loadingSource = value;
  DateTime? _lastPlayKickAt;
  DateTime? _lastSilentRecoverAt;
  DateTime? _lastUserPauseAt;
  DateTime? get _transitionArmedAt => _crossfadeRuntime.transitionArmedAt;
  set _transitionArmedAt(DateTime? value) =>
      _crossfadeRuntime.transitionArmedAt = value;
  final ResumePositionStore _resumeStore = ResumePositionStore();
  /// Compatibility aliases — resume state lives in [_resumeStore].
  int get _resumePositionMs => _resumeStore.lastPositionMs;
  set _resumePositionMs(int value) => _resumeStore.lastPositionMs = value;
  String? get _resumeSongId => _resumeStore.lastSongId;
  set _resumeSongId(String? value) => _resumeStore.lastSongId = value;
  DateTime? get _lastResumePersist => _resumeStore.lastPersistAt;
  set _lastResumePersist(DateTime? value) => _resumeStore.lastPersistAt = value;
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
  String? get _lastCrossfadeDurationUnavailableSongId =>
      _crossfadeRuntime.lastDurationUnavailableSongId;
  set _lastCrossfadeDurationUnavailableSongId(String? value) =>
      _crossfadeRuntime.lastDurationUnavailableSongId = value;

  final FocusInterruptionRuntime _focusInterruption = FocusInterruptionRuntime();
  /// Compatibility aliases — duck / focus-loss state lives in [_focusInterruption].
  bool get _isDucked => _focusInterruption.isDucked;
  set _isDucked(bool value) => _focusInterruption.isDucked = value;
  bool get _unduckPendingAfterCrossfade =>
      _focusInterruption.unduckPendingAfterCrossfade;
  set _unduckPendingAfterCrossfade(bool value) =>
      _focusInterruption.unduckPendingAfterCrossfade = value;
  DateTime? get _focusLostAt => _focusInterruption.focusLostAt;
  set _focusLostAt(DateTime? value) => _focusInterruption.focusLostAt = value;
  int get _focusResumeGeneration => _focusInterruption.resumeGeneration;
  set _focusResumeGeneration(int value) =>
      _focusInterruption.resumeGeneration = value;
  int _volumeFadeGen = 0;
  static const double _duckLevel = FocusInterruptionRuntime.duckLevel;
  final AudioFocusSettings _audioFocusSettings = AudioFocusSettings();
  /// Compatibility aliases — focus prefs live in [_audioFocusSettings].
  bool get _audioFocusAutomationEnabled =>
      _audioFocusSettings.automationEnabled;
  set _audioFocusAutomationEnabled(bool value) =>
      _audioFocusSettings.automationEnabled = value;
  int get _audioFocusLevel => _audioFocusSettings.level;
  set _audioFocusLevel(int value) => _audioFocusSettings.level = value;
  bool get audioFocusAutomationEnabled =>
      _audioFocusSettings.automationEnabled;
  int get audioFocusLevel => _audioFocusSettings.clampedLevel;

  Future<void> setAudioFocusAutomation({bool? automatic, int? level}) async {
    if (automatic != null) _audioFocusSettings.setAutomationEnabled(automatic);
    if (level != null) _audioFocusSettings.setLevel(level);
    await _audioFocusSettings.persist();
    notifyListeners();
  }
  static const int _duckFadeMs = FocusInterruptionRuntime.duckFadeMs;
  /// Short transport fade for user pause / resume (keeps next/seek snappy).
  static const int _transportFadeMs = 220;
  static const Duration _autoResumeMaxFocusLoss =
      FocusInterruptionRuntime.autoResumeMaxFocusLoss;

  final PlaybackHistorySession _historySession = PlaybackHistorySession();

  double get volume => _volume;
  bool get audioLevelingEnabled => _audioLevelingEnabled;
  double get audioLevelingTargetRmsDbfs => _audioLevelingTargetRmsDbfs;

  Future<void> setAudioLevelingEnabled(bool enabled) async {
    if (!_levelingSettings.setEnabled(enabled)) return;
    await _levelingSettings.persist();
    await _refreshTrackLevelingFor(currentSong);
    notifyListeners();
  }

  Future<void> setAudioLevelingTargetRmsDbfs(double target) async {
    if (!_levelingSettings.setTargetRmsDbfs(target)) return;
    await _levelingSettings.persist();
    await _refreshTrackLevelingFor(currentSong);
    notifyListeners();
  }

  /// Refresh the current song's cached leveling trim after a scan or track change.
  /// This phase only attenuates loud tracks; it never boosts above the existing
  /// EQ/preamp master, so cached analysis cannot introduce a new clipping spike.
  Future<void> refreshTrackLevelingFor(Song? song) =>
      _refreshTrackLevelingFor(song);

  Future<void> _refreshTrackLevelingFor(Song? song) async {
    final generation = ++_trackLevelingGeneration;
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _transportInFlight ||
        _loadingSource) {
      return; // The current transition/transport retains volume ownership.
    }

    // If the next track has not been scanned for this target, retain the
    // current conservative trim rather than suddenly restoring full level.
    var nextScale = _audioLevelingEnabled && song != null
        ? _trackLevelingScale
        : 1.0;
    if (_audioLevelingEnabled && song != null) {
      final cached = await _loudnessService.getCached(song);
      if (generation != _trackLevelingGeneration ||
          currentSong?.id != song.id ||
          _crossfadeInProgress ||
          _automaticCrossfadeInFlight ||
          _repeatSelfHandoffInFlight ||
          _transportInFlight ||
          _loadingSource) {
        // A transition may have started while the cached result was loading.
        // Its finalizer will refresh the newly committed track.
        return;
      }
      if (cached != null &&
          (cached.targetRmsDbfs - _audioLevelingTargetRmsDbfs).abs() < 0.001) {
        // Deliberately apply cuts only. Positive gain recommendations are
        // shown to the user but not applied until a peak-safe gain stage exists.
        final safeGainDb = cached.gainDb.clamp(-12.0, 0.0).toDouble();
        nextScale = math.pow(10.0, safeGainDb / 20.0).toDouble();
      }
    }
    if (generation != _trackLevelingGeneration) return;
    _trackLevelingScale = nextScale;
    _eqPreampScale =
        (_eqPreampUserScale * _trackLevelingScale).clamp(0.0, 1.0).toDouble();
    try {
      if (!_crossfadeInProgress &&
          !_automaticCrossfadeInFlight &&
          !_repeatSelfHandoffInFlight &&
          !_transportInFlight &&
          !_loadingSource) {
        await audioPlayer.setVolume(_effectiveCrossfadeMaster);
      }
    } catch (_) {}
  }
  List<Song> get queue => _queueStore.unmodifiable;
  int get queueIndex => _queueStore.index;
  List<Song> get upcomingQueue => _queueStore.upcoming;
  bool get shuffleEnabled => _queueStore.shuffleEnabled;
  bool get modeCrossfadeAllowed => _modeCrossfadeAllowed;
  bool get modeShuffleAllowed => _modeShuffleAllowed;
  bool get modePreciseResume => _modePreciseResume;

  void attachModes(ModeProvider modes) {
    _modes?.removeListener(_onModesChangedForSessions);
    _modes = modes;
    modes.addListener(_onModesChangedForSessions);
    _podcastSession.sync(modes: modes, song: currentSong, position: currentPosition, playing: isPlaying);
    _audiobookSession.sync(modes: modes, song: currentSong, position: currentPosition, playing: isPlaying);
    modes.onPlaybackStarted(currentSong, position: currentPosition);
  }

  void _onModesChangedForSessions() {
    final modes = _modes;
    if (modes == null) return;
    _podcastSession.sync(modes: modes, song: currentSong, position: currentPosition, playing: isPlaying);
    _audiobookSession.sync(modes: modes, song: currentSong, position: currentPosition, playing: isPlaying);
  }

  bool get podcastSessionActive => _podcastSession.isActive;
  bool get audiobookSessionActive => _audiobookSession.isActive;
  /// User setting AND mode policy both allow crossfade.
  bool get effectiveCrossfadeEnabled =>
      _crossfadeEnabled && _modeCrossfadeAllowed;

  /// DJ handoffs are live only when DJ has an active transition feature
  /// and the current Mode still permits crossfade-style handoffs.
  bool get _djHandoffsLive =>
      _modeCrossfadeAllowed && _djHandoff.anyFeatureActive;
  bool get effectiveShuffleEnabled =>
      _shuffleEnabled && _modeShuffleAllowed;

  PlaybackRepeatMode get repeatMode => _repeatMode;
  bool get canCrossfadeNext {
    if (!effectiveCrossfadeEnabled) return false;
    if (_crossfadeInProgress || _queue.isEmpty || _queueIndex < 0) return false;
    if (_repeatMode == PlaybackRepeatMode.one) return false;
    if (_queueIndex < _queue.length - 1) return true;
    if (_repeatMode == PlaybackRepeatMode.all && _queue.length > 1) return true;
    return false;
  }

  /// Seamless loop: same song on the idle engine when repeat-one + crossfade.
  bool get canRepeatSelfHandoff {
    if (!effectiveCrossfadeEnabled) return false;
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

  /// Last DJ handoff snapshot for Now Playing "why this transition" chip.
  DateTime? get lastDjHandoffAt => _lastDjHandoffAt;
  String? get lastDjStrategy => _lastDjStrategy;
  double? get lastDjTransitionScore => _lastDjTransitionScore;
  double? get lastDjTransitionConfidence => _lastDjTransitionConfidence;
  List<String> get lastDjTransitionRisks =>
      List<String>.unmodifiable(_lastDjTransitionRisks);

  /// True for a short window after a DJ plan was applied (UI chip visibility).
  bool get hasRecentDjTransition => _djHandoff.hasRecentHandoff;
  bool get transitionInProgress => _crossfadeRuntime.isLive;

  /// Phase 2: normal listening is always Engine A. Engine B is only for an
  /// in-progress crossfade (or a track that was handed off via crossfade).
  bool get isEngineA => _activeIsA;

  /// True when we have a saved mid-track position for the current queue song.
  bool get canContinueListening {
    // Continue-listening is the user-facing precise-resume affordance. Keep it
    // hidden when the active Mode explicitly starts content from the beginning.
    if (!_modePreciseResume) return false;
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
    // The command must obey the same Mode policy as the visible affordance.
    if (!_modePreciseResume) return Future<bool>.value(false);
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


  static const _repeatModeKey = 'playback_repeat_mode';
  static const MethodChannel _systemVolumeChannel = MethodChannel('com.aetherion.resonate/media_store');

  MusicProvider({this.audioHandler}) {
    // Players + Android effects are constructed by [EnginePair].
    _audioEffectsController = AudioEffectsController(
      equalizerA: _equalizerA,
      equalizerB: _equalizerB,
      loudnessA: _loudnessA,
      loudnessB: _loudnessB,
    );
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
      _shuffleEnabled = prefs.getBool(QueueStore.shuffleEnabledKey) ?? false;
      await _levelingSettings.load(prefs);
      await _audioFocusSettings.load(prefs);
      final repeat = prefs.getString(_repeatModeKey) ?? 'off';
      _repeatMode = switch (repeat) { 'all' => PlaybackRepeatMode.all, 'one' => PlaybackRepeatMode.one, _ => PlaybackRepeatMode.off };
      // Crossfade preferences are owned and restored by CrossfadeProvider.
      // MusicProvider remains the playback authority but does not persist a
      // second copy of these UI preferences.
      await _resumeStore.load(prefs);
      await _syncSystemVolume();
      if (currentSong != null) unawaited(_refreshTrackLevelingFor(currentSong));
      // Skip syncSavedAudioEffects at startup — it awaits eq.parameters and
      // then fires during the first play, crashing the Activity.

      if (!const ['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(_crossfadeFadeType)) _crossfadeFadeType = 'linear';
      notifyListeners();
    } catch (e) { debugPrint('Playback settings load failed: $e'); }
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    if (enabled) {
      _queueStore.shuffleUpcoming();
    }
    await _persistPlaybackModes(); await _persistQueue(); notifyListeners();
  }

  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    if (_repeatMode == mode) return;
    final transitionActive = _crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _crossfadePreloadInFlight ||
        _preloadedNextSongId != null;
    // Repeat mode changes the meaning of an in-flight transition. In
    // particular, turning Repeat One off must invalidate its self-loop before
    // that stale operation can commit or fall back to replaying the old track.
    if (transitionActive) _cancelAutomaticPlaybackWork();
    _repeatMode = mode;
    await _persistPlaybackModes();
    unawaited(_synchronizeModePlaybackBoundary());
    notifyListeners();
  }

  Future<void> _persistPlaybackModes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(QueueStore.shuffleEnabledKey, _shuffleEnabled);
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
    DjPolicy policy = DjPolicy.balanced,
  }) {
    _djPolicy = policy;
    final wasActive =
        _djBeatAlignActive || _djTempoMatchActive || _djSfxActive;
    _djBeatAlignActive = beatAlignActive;
    _djTempoMatchActive = tempoMatchActive;
    _djMaxStretchPercent = maxStretchPercent.clamp(3, 20);
    _djSfxActive = sfxActive;
    _djAnalysis = analysis;
    if (wasActive &&
        !beatAlignActive &&
        !tempoMatchActive &&
        !sfxActive) {
      unawaited(_recoverDjEngineState(reason: 'dj_mode_disabled'));
    }
  }


  /// If UI says playing but engine volume is near zero outside a crossfade, unstick.
  void _maybeRecoverSilentPlayback() {
    _forceClearStuckTransition(reason: 'silent_recover_probe');
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _transportInFlight ||
        _loadingSource ||
        _djSfxEngaged ||
        _isDucked ||
        _recentlyUserPaused) {
      return;
    }
    if (!_userWantsPlaying) return;
    try {
      final active = audioPlayer;
      final dur = active.duration ?? currentDuration;
      final pos = active.position;
      // Near end or completed: let completion / soft-loop own the next action.
      if (active.processingState == ProcessingState.completed) return;
      if (dur != null &&
          dur > Duration.zero &&
          pos >= dur - const Duration(seconds: 3)) {
        return;
      }
      // Playing but muted, or wants play but engine not playing (BT route lag).
      final mutedWhilePlaying =
          active.playing && active.volume < 0.05;
      final wantsButStopped = !active.playing;
      if (!mutedWhilePlaying && !wantsButStopped) return;
      final now = DateTime.now();
      final cooldown = wantsButStopped
          ? const Duration(seconds: 4)
          : const Duration(seconds: 5);
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
    // Recovery is asynchronous and may overlap a manual track selection. It
    // must never restore master volume on an engine captured before that
    // selection, or it can make the old track audible again.
    final recoveryTransportEpoch = _userTransportEpoch;
    bool wasPreempted() => recoveryTransportEpoch != _userTransportEpoch;
    try {
      await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
      if (wasPreempted()) return;
    } catch (_) {}
    try {
      await _restoreDjTransitionSfx();
      if (wasPreempted()) return;
    } catch (_) {}
    try {
      final active = audioPlayer;
      final inactive = inactivePlayer;
      final vol = _eqPreampScale.clamp(0.05, 1.0);
      try {
        await active.setSpeed(1.0);
      } catch (_) {}
      if (wasPreempted()) return;
      try {
        await inactive.setSpeed(1.0);
      } catch (_) {}
      if (wasPreempted()) return;
      try {
        if ((_userWantsPlaying || active.playing) && active.volume < vol * 0.85) {
          await active.setVolume(vol);
        }
      } catch (_) {}
      if (wasPreempted()) return;
      try {
        await inactive.setVolume(0.0);
      } catch (_) {}
      if (wasPreempted()) return;
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      if (wasPreempted()) return;
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


  /// Called by Modes via [ModePlaybackPort]. Soft gates only — never forces play.
  void applyModePlaybackPolicy({
    required bool crossfadeAllowed,
    required bool shuffleAllowed,
    required bool preciseResume,
  }) {
    final crossfadeWasAllowed = _modeCrossfadeAllowed;
    final changed = _modePlaybackPolicy.update(
      crossfadeAllowed: crossfadeAllowed,
      shuffleAllowed: shuffleAllowed,
      preciseResume: preciseResume,
    );

    // A Mode boundary is an authority boundary. If the new Mode blocks
    // crossfade (notably Podcast/Audiobook), an already-running automatic
    // A/B/DJ handoff must be invalidated rather than being allowed to finish
    // under the previous Mode's policy. User transport remains unaffected.
    if (crossfadeWasAllowed &&
        !crossfadeAllowed &&
        (_crossfadeInProgress ||
            _automaticCrossfadeInFlight ||
            _repeatSelfHandoffInFlight ||
            _crossfadePreloadInFlight ||
            _preloadedNextSongId != null)) {
      _cancelAutomaticPlaybackWork();
      unawaited(ResonateDiagnostics.record('mode_crossfade_cancelled', {
        'reason': 'mode_policy_disallowed_crossfade',
        'djActive': _djBeatAlignActive ||
            _djTempoMatchActive ||
            _djSfxActive,
        'songId': currentSong?.id,
      }));
    }

    if (changed) {
      unawaited(_synchronizeModePlaybackBoundary());
      notifyListeners();
    }
  }

  /// Reconcile native loop state and stream ownership when Modes changes the
  /// playback policy. AudioPlayer loop mode persists across Mode boundaries;
  /// without this, Audiobook's LoopMode.one can leak into Normal mode.
  Future<void> _synchronizeModePlaybackBoundary() async {
    final generation = ++_modeBoundaryGeneration;
    // A policy update must never pause an engine after a new handoff has
    // started. Re-check ownership after each await, not only at method exit.
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight) return;
    final active = audioPlayer;
    final idle = inactivePlayer;
    bool ownsBoundary() =>
        generation == _modeBoundaryGeneration &&
        identical(active, audioPlayer) &&
        identical(idle, inactivePlayer) &&
        !_crossfadeInProgress &&
        !_automaticCrossfadeInFlight &&
        !_repeatSelfHandoffInFlight;

    final activeLoop = effectiveCrossfadeEnabled
        ? LoopMode.off
        : switch (_repeatMode) {
            PlaybackRepeatMode.one => LoopMode.one,
            // Repeat-all advances the app queue; native LoopMode.all on a single
            // source would repeat the current track instead of advancing.
            PlaybackRepeatMode.all => LoopMode.off,
            PlaybackRepeatMode.off => LoopMode.off,
          };
    try { await idle.pause(); } catch (_) {}
    if (!ownsBoundary()) return;
    try { await idle.setVolume(0.0); } catch (_) {}
    if (!ownsBoundary()) return;
    try { await idle.setLoopMode(LoopMode.off); } catch (_) {}
    if (!ownsBoundary()) return;
    try { await active.setLoopMode(activeLoop); } catch (_) {}
    if (!ownsBoundary()) return;
    if (!_isDucked) {
      try { await active.setVolume(_effectiveCrossfadeMaster.clamp(0.0, 1.0)); } catch (_) {}
    }
    if (!ownsBoundary()) return;
    _bindActivePlayerStreams();
    _publishServiceState();
  }

  Future<void> setCrossfadeEnabled(bool enabled) async {
    final wasEnabled = _crossfadeEnabled;
    _crossfadeEnabled = enabled;
    if (enabled && _crossfadeDurationMs <= 0) _crossfadeDurationMs = 3000;

    // The user's crossfade switch is a playback authority boundary too.
    // Turning it off while automatic A/B/DJ work is active must invalidate
    // that work immediately rather than letting a transition finish under
    // a setting the user has already disabled.
    if (wasEnabled &&
        !enabled &&
        (_crossfadeInProgress ||
            _automaticCrossfadeInFlight ||
            _repeatSelfHandoffInFlight ||
            _crossfadePreloadInFlight ||
            _preloadedNextSongId != null)) {
      _cancelAutomaticPlaybackWork();
      unawaited(ResonateDiagnostics.record('crossfade_cancelled', {
        'reason': 'user_crossfade_disabled',
        'djActive': _djBeatAlignActive ||
            _djTempoMatchActive ||
            _djSfxActive,
        'songId': currentSong?.id,
      }));
    }

    unawaited(_synchronizeModePlaybackBoundary());
    notifyListeners();
  }

  Future<void> setCrossfadeDuration(int milliseconds) async {
    _crossfadeDurationMs = milliseconds.clamp(500, 12000).toInt();
    _crossfadeEnabled = true;
    notifyListeners();
  }

  Future<void> setCrossfadeFadeType(String value) async {
    if (!const ['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(value)) return;
    _crossfadeFadeType = value;
    notifyListeners();
  }

  Future<void> syncSavedAudioEffects() async {
    try { await _audioEffectsController.syncAll(); } catch (e) { debugPrint('Saved audio effects sync failed: $e'); }
  }


  /// Public: re-claim focus and restore volume if playback went silent while UI moved.
  Future<void> ensureAudiblePlayback() async {
    try {
      if (_recentlyUserPaused) return;
      if (!_userWantsPlaying) return;
      // Do not fight an active sleep-timer fade-out.
      if (_sleepFadeScale < 0.999) return;
      await _claimAudioFocus(reason: 'ensure_audible');
      final vol = (_eqPreampScale * _sleepFadeScale).clamp(0.05, 1.0);
      if (audioPlayer.volume < vol * 0.85) {
        await audioPlayer.setVolume(vol);
      }
      if (_userWantsPlaying && !audioPlayer.playing) {
        await audioPlayer.play();
      }
    } catch (e) {
      debugPrint('ensureAudiblePlayback: $e');
    }
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
            // Calls / exclusive media: pause and invalidate any pending auto-resume.
            _focusResumeGeneration++;
            _focusLostAt = DateTime.now();
            unawaited(pause(source: 'system'));
          } else if (event.type == AudioInterruptionType.duck) {
            // Notifications / nav / transient: configurable soft duck.
            if (_audioFocusAutomationEnabled) unawaited(_duckForInterruption());
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
            final lostDuration = lostAt == null
                ? null
                : DateTime.now().difference(lostAt);
            final resumeLimit = _audioFocusLevel == 3
                ? const Duration(seconds: 30)
                : _autoResumeMaxFocusLoss;
            final mayAutoResume = _audioFocusAutomationEnabled && _audioFocusLevel >= 3;
            final lostLong = lostDuration != null && lostDuration > resumeLimit;
            if (!mayAutoResume || lostLong) {
              // Long call: do not surprise-resume; user taps play when ready.
              _userWantsPlaying = false;
              unawaited(ResonateDiagnostics.record('audio_focus_event', {
                'action': mayAutoResume ? 'skip_auto_resume_long_focus_loss' : 'manual_resume_required',
                'focusLevel': _audioFocusLevel,
                'automationEnabled': _audioFocusAutomationEnabled,
                'lostMs': lostDuration?.inMilliseconds,
              }));
              return;
            }
            if (_userWantsPlaying) {
              final generation = ++_focusResumeGeneration;
              unawaited(_resumeAfterSystemFocus(generation: generation));
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

  double get _effectiveCrossfadeMaster {
    final preamp = (_eqPreampScale * _sleepFadeScale).clamp(0.0, 1.0).toDouble();
    if (!_isDucked) return preamp;
    final duck = _audioFocusLevel == 1 ? 0.18 : _duckLevel;
    return (duck * preamp).clamp(0.0, 0.45).toDouble();
  }

  bool get _transitionLive =>
      _crossfadeInProgress ||
      _automaticCrossfadeInFlight ||
      _repeatSelfHandoffInFlight;

  /// Apply current master gain (preamp × sleep fade × duck) to the active engine.
  Future<void> _applyActiveMasterVolume() async {
    try {
      await audioPlayer.setVolume(_effectiveCrossfadeMaster.clamp(0.0, 1.0));
    } catch (_) {}
  }

  /// Silence the idle (non-active) engine. Safe during transitions.
  Future<void> _silenceIdleEngine() async {
    try {
      await inactivePlayer.setVolume(0.0);
    } catch (_) {}
  }

  void _clearTransitionFlags({bool clearRepeatSelf = true}) {
    _crossfadeRuntime.clearFlags(clearRepeatSelf: clearRepeatSelf);
    _endOfTrackWatchdog?.cancel();
    _endOfTrackWatchdog = null;
  }


  /// Sleep-timer fade (1.0 = no fade). Does not change system volume.
  Future<void> setSleepFadeScale(double scale) async {
    _sleepFadeScale = scale.clamp(0.0, 1.0).toDouble();
    if (_transitionLive) {
      // Crossfade / handoff path reads _effectiveCrossfadeMaster on each step.
      return;
    }
    await _applyActiveMasterVolume();
  }

  Future<void> clearSleepFade() async {
    if (_sleepFadeScale >= 0.999) return;
    await setSleepFadeScale(1.0);
  }

  Future<void> _duckForInterruption() async {
    _unduckPendingAfterCrossfade = false;
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
      // Let the crossfade own volumes; mark ducked so we restore after.
      _isDucked = true;
      return;
    }
    _isDucked = true;
    final duck = _audioFocusLevel == 1 ? 0.18 : _duckLevel;
    final target = (duck * _eqPreampScale).clamp(0.05, 0.45);
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
      _unduckPendingAfterCrossfade = false;
      return;
    }
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
      // Keep both engines at the ducked gain until the handoff has committed.
      // Clearing _isDucked here would make the incoming engine jump to full gain.
      _unduckPendingAfterCrossfade = true;
      return;
    }
    _unduckPendingAfterCrossfade = false;
    try {
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
        await audioPlayer.setVolume(_effectiveCrossfadeMaster.clamp(0.0, 1.0));
      } catch (_) {}
    }
  }

  /// Re-claim session then resume after a call / exclusive focus loss.
  Future<void> _resumeAfterSystemFocus({required int generation}) async {
    // Let Android settle before resuming. Do not setActive(true) here: doing so
    // can reclaim focus from another music app that has just taken ownership.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (generation != _focusResumeGeneration || !_userWantsPlaying) return;
    _isDucked = false;
    try {
      await audioPlayer.setVolume(_effectiveCrossfadeMaster.clamp(0.0, 1.0));
    } catch (_) {}
    await resumePlayback(source: 'system');
    // Nudge volume again only if no newer focus event superseded this recovery.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (generation == _focusResumeGeneration && _userWantsPlaying && !_crossfadeInProgress) {
      try {
        await audioPlayer.setVolume(_effectiveCrossfadeMaster.clamp(0.0, 1.0));
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
      final ids = prefs.getStringList(QueueStore.savedQueueIdsKey) ?? const <String>[];
      await _resumeStore.load(prefs);
      if (ids.isEmpty || currentSong != null || _queue.isNotEmpty) return;
      final savedIndex = prefs.getInt(QueueStore.savedQueueIndexKey) ?? 0;
      final songs = await _database.getAllSongs();
      await _visibility.load();
      final visibleSongs = _visibility.filter(songs, (song) => song.id);
      final byId = <String, Song>{for (final song in visibleSongs) song.id: song};
      final restored = ids.map((id) => byId[id]).whereType<Song>().toList();
      if (restored.isEmpty) return;
      _queue = restored;
      _queueIndex = savedIndex.clamp(0, restored.length - 1).toInt();
      currentSong = _queue[_queueIndex];
      unawaited(_refreshTrackLevelingFor(currentSong));
      currentDuration = currentSong!.duration;
      // Restore last known position for the current song (if any).
      if (_modePreciseResume &&
          _resumeSongId == currentSong!.id &&
          _resumePositionMs > 1500) {
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
    await _queueStore.persist();
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
        // Reflect native play in UI only when the user still wants playback.
        // Never re-assert _userWantsPlaying here — that made pause feel broken
        // when a second engine or late stream event flipped intent back on.
        if (_userWantsPlaying && !isPlaying) {
          isPlaying = true;
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
          !_recentlyUserPaused &&
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
            if (_transitionLive) return;
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

        // Publish the completion to Modes before transport advances the queue.
        // The current song is still the completed content at this point, so
        // Motivation can emit speechCompleted/musicFollowupSuggested without
        // Modes gaining any authority over queue advancement.
        final completedSong = currentSong;
        if (completedSong != null && completedSong.id == completedSongId) {
          _modes?.onPlaybackCompleted(completedSong);
        }

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
        if (_crossfadeInProgress ||
            _automaticCrossfadeInFlight ||
            _repeatSelfHandoffInFlight) {
          // Outgoing finished mid-fade. For repeat-one this is expected (self
          // handoff); for A→B we continue after commit without a second advance.
          _completionObservedDuringCrossfade = true;
          _completionObservedSongId = completedSongId;
          if (_repeatMode == PlaybackRepeatMode.one ||
              _repeatSelfHandoffInFlight) {
            // Do not treat as "need to go to next queue item".
            _lastCompletionSongId = completedSongId;
          }
          // Screen-off / background: keep idle engine silent so completion on
          // the outgoing does not leave two audible sources.
          unawaited(_silenceIdleEngine());
        } else if (!_completionAdvanceInProgress) {
          unawaited(onTrackEnded(completedSongId));
        }
      }
    });
    _currentIndexSubscription?.cancel();
    _currentIndexSubscription = player.currentIndexStream.listen((index) {
      if (index == null || _crossfadeEnabled || _crossfadeInProgress) return;
      if (!_gaplessWindow.active || _transportInFlight) return;
      if (index < 0 || index >= _gaplessWindow.songIds.length) return;
      final songId = _gaplessWindow.songIds[index];
      final globalIndex = _queue.indexWhere((s) => s.id == songId);
      if (globalIndex < 0) return;
      if (globalIndex == _queueIndex && currentSong?.id == songId) return;
      _queueIndex = globalIndex;
      currentSong = _queue[globalIndex];
      unawaited(_refreshTrackLevelingFor(currentSong));
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
        'windowStart': _gaplessWindow.start,
        'songId': currentSong?.id,
      }));
    });

    _positionSubscription = player.positionStream.listen((position) {
      if (currentPosition != position) {
        currentPosition = position;
      _forceClearStuckTransition(reason: 'position_tick');
      _maybeRecoverSilentPlayback();
        if (_historySession.activeEvent != null) {
          _historySession.positionMs = position.inMilliseconds;
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
    final raw = currentPosition.inMilliseconds > 0
        ? currentPosition.inMilliseconds
        : _historySession.positionMs;
    final cap = currentDuration?.inMilliseconds ?? 0;
    final shouldWrite = _resumeStore.record(
      songId: song.id,
      positionMs: raw,
      durationMs: cap,
      force: force,
    );
    if (shouldWrite) unawaited(_resumeStore.persist());
  }

  Future<void> _loadResumeMap(SharedPreferences prefs) async {
    await _resumeStore.loadMap(prefs);
  }

  Future<void> _saveResumeMap() async {
    await _resumeStore.persistMapOnly();
  }

  /// Position to resume a specific song, if known (per-song map or last resume).
  int? resumePositionFor(String songId) => _resumeStore.positionFor(songId);

  void _maybeStartAutomaticCrossfade(Duration position) {
    if (!effectiveCrossfadeEnabled || !audioPlayer.playing) return;
    if (_userTransportPending) return;
    // Never arm auto-crossfade while the user is driving transport or loading.
    if (_transportInFlight || _loadingSource) return;
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight) {
      return;
    }
    // Only the active engine's loaded-source duration is trustworthy for
    // crossfade timing. currentDuration may be metadata or belong to the prior
    // source after a background/route transition, so never use it to arm a fade.
    final duration = audioPlayer.duration;
    if (duration == null || duration <= Duration.zero) {
      final songId = currentSong?.id;
      if (songId != null && _lastCrossfadeDurationUnavailableSongId != songId) {
        _lastCrossfadeDurationUnavailableSongId = songId;
        unawaited(ResonateDiagnostics.record('crossfade_trigger_skipped_duration_unavailable', {
          'songId': songId,
          'positionMs': position.inMilliseconds,
          'metadataDurationMs': currentDuration?.inMilliseconds,
          'engine': _activeIsA ? 'A' : 'B',
          'playing': audioPlayer.playing,
          'reason': 'active_engine_duration_unavailable',
        }));
      }
      return;
    }
    _lastCrossfadeDurationUnavailableSongId = null;
    final remaining = duration - position;
    if (remaining <= Duration.zero) return;

    // Repeat-one + crossfade: dual-engine A→B self-handoff (same song).
    // Soft single-engine loop is the fallback if the idle engine load times out.
    if (_repeatMode == PlaybackRepeatMode.one) {
      if (!effectiveCrossfadeEnabled ||
          _repeatSelfHandoffInFlight ||
          _transportInFlight ||
          _crossfadeInProgress) {
        return;
      }
      if (currentSong == null) return;
      // Keep the blend short so we start near the true end (not mid-outro).
      final loopMs = _crossfadeDurationMs.clamp(1600, 5500);
      final triggerMs = (loopMs + 500).clamp(1500, 4500);
      if (remaining > Duration(milliseconds: triggerMs)) return;
      // Do not start if already past the end window.
      if (remaining < const Duration(milliseconds: 400)) return;
      _repeatSelfHandoffInFlight = true;
      _automaticCrossfadeInFlight = true;
      _transitionArmedAt = DateTime.now();
      unawaited(_runRepeatSelfDualOrSoft(loopMs: loopMs));
      return;
    }

    if (!canCrossfadeNext) return;

    final preloadMs = (_crossfadeDurationMs + 10000).clamp(10000, 28000);
    final fadeArmMs = _crossfadeDurationMs + 2000;
    if (remaining <= Duration(milliseconds: preloadMs) &&
        remaining > Duration(milliseconds: fadeArmMs)) {
      unawaited(_preloadNextForCrossfade());
    }

    final djActive = _djBeatAlignActive || _djTempoMatchActive || _djSfxActive;
    final effectiveXfMs =
        (djActive ? _crossfadeDurationMs.clamp(500, 6500) : _crossfadeDurationMs)
            .toInt();
    final startMarginMs = (1200 + (effectiveXfMs ~/ 10)).clamp(1500, 3000);
    final triggerMs = (effectiveXfMs + startMarginMs).clamp(2000, 16000);
    if (remaining > Duration(milliseconds: triggerMs)) return;
    if (remaining < const Duration(milliseconds: 1200)) return;
    _automaticCrossfadeInFlight = true;
    _transitionArmedAt = DateTime.now();
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

  /// Prefer dual-engine A→B self-crossfade; fall back to soft loop on timeout.
  Future<void> _runRepeatSelfDualOrSoft({required int loopMs}) async {
    final generation = _repeatSelfGeneration;
    final song = currentSong;
    if (song == null) {
      _automaticCrossfadeInFlight = false;
      _repeatSelfHandoffInFlight = false;
      return;
    }
    final ms = loopMs.clamp(1200, 4000);
    final ok = await _performRepeatSelfDual(
      milliseconds: ms,
      generation: generation,
    ).timeout(
      Duration(milliseconds: ms + 4500),
      onTimeout: () {
        debugPrint('repeat self dual timed out');
        // Future.timeout does not cancel the underlying native operation.
        // Invalidate it instead of starting a competing soft loop.
        if (_repeatSelfGeneration == generation) {
          _repeatSelfGeneration++;
          _automaticCrossfadeInFlight = false;
          _crossfadeInProgress = false;
          _repeatSelfHandoffInFlight = false;
          _repeatSelfHandoffArmed = false;
          _repeatSelfTargetSongId = null;
          unawaited(_recoverCancelledRepeatSelfEngine());
        }
        return false;
      },
    );
    if (_repeatSelfGeneration != generation ||
        !_repeatSelfHandoffInFlight ||
        !effectiveCrossfadeEnabled ||
        _repeatMode != PlaybackRepeatMode.one) {
      return;
    }
    if (ok) {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
      _repeatSelfHandoffInFlight = false;
      _repeatSelfHandoffArmed = false;
      // Outgoing engine often hits completed mid-ramp. Do not advance to B.
      _completionObservedDuringCrossfade = false;
      if (song.id.isNotEmpty) {
        _lastCompletionSongId = song.id;
      }
      return;
    }
    // Only genuine load/play failures may use the single-engine fallback.
    // Cancellation or a changed mode/setting must never restart Track A.
    if (_repeatSelfGeneration != generation ||
        !_repeatSelfHandoffInFlight ||
        !effectiveCrossfadeEnabled ||
        _repeatMode != PlaybackRepeatMode.one) {
      return;
    }
    unawaited(ResonateDiagnostics.record('repeat_self_fallback', {
      'reason': 'dual_load_or_play_failed',
      'songId': song.id,
    }));
    await _runRepeatSelfSoftLoop(
      loopMs: math.min(ms, 2000),
      generation: generation,
    );
  }

  Future<bool> _performRepeatSelfDual({
    required int milliseconds,
    required int generation,
  }) async {
    final song = currentSong;
    if (song == null || song.filePath.trim().isEmpty) return false;
    if (!audioPlayer.playing && !_userWantsPlaying) return false;
    _crossfadeInProgress = true;
    final outgoing = audioPlayer;
    final incoming = inactivePlayer;
    final incomingEq = inactiveEqualizer;
    final incomingLoud = inactiveLoudnessEnhancer;
    final master = _effectiveCrossfadeMaster.clamp(0.05, 1.0).toDouble();
    final ms = milliseconds.clamp(1200, 4000);
    try {
      try {
        await incoming.stop();
      } catch (_) {}
      // Load with a hard timeout — same MediaStore URI can hang on some OEMs.
      await _loadSingle(
        incoming,
        incomingEq,
        incomingLoud,
        song,
        start: false,
      ).timeout(const Duration(milliseconds: 2800));
      if (!_repeatSelfTransitionCurrent(generation)) {
        await _abortRepeatSelfEngine(incoming);
        return false;
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
        incoming.play();
      } catch (_) {}
      for (var i = 0; i < 8 && !incoming.playing; i++) {
        await Future<void>.delayed(Duration(milliseconds: 30 + i * 25));
        try {
          incoming.play();
        } catch (_) {}
      }
      if (!incoming.playing || !_repeatSelfTransitionCurrent(generation)) {
        await _abortRepeatSelfEngine(incoming);
        return false;
      }

      unawaited(ResonateDiagnostics.record('repeat_self_ramp', {
        'mode': 'dual',
        'songId': song.id,
        'ms': ms,
        'fromEngine': _activeIsA ? 'A' : 'B',
        'toEngine': _activeIsA ? 'B' : 'A',
      }));

      final steps = (ms / 40).round().clamp(10, 60);
      final stepMs = (ms / steps).round().clamp(20, 60);
      final startOut = outgoing.volume.clamp(0.05, 1.0);
      for (var i = 1; i <= steps; i++) {
        if (!_repeatSelfTransitionCurrent(generation)) {
          await _abortRepeatSelfEngine(incoming);
          return false;
        }
        final t = i / steps;
        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);
        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);
        try {
          await outgoing.setVolume((startOut * math.cos(outT * (math.pi / 2.0))).clamp(0.0, 1.0));
        } catch (_) {}
        try {
          await incoming.setVolume((master * math.sin(inT * (math.pi / 2.0))).clamp(0.0, 1.0));
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }

      if (!_repeatSelfTransitionCurrent(generation)) {
        await _abortRepeatSelfEngine(incoming);
        return false;
      }
      _activeIsA = !_activeIsA;
      _lastCompletionSongId = null;
      currentPosition = incoming.position;
      currentDuration = song.duration;
      isPlaying = incoming.playing || _userWantsPlaying;
      _bindActivePlayerStreams();
      _publishServiceState();
      notifyListeners();

      // A user command can arrive just after the engine swap. Do not let this
      // old handoff's cleanup pause or retune an engine now owned by that command.
      if (generation != _repeatSelfGeneration) return true;
      try {
        await outgoing.pause();
      } catch (_) {}
      if (generation != _repeatSelfGeneration) return true;
      try {
        await outgoing.setVolume(master);
      } catch (_) {}
      if (generation != _repeatSelfGeneration) return true;
      try {
        await outgoing.setSpeed(1.0);
      } catch (_) {}
      if (generation != _repeatSelfGeneration) return true;
      try {
        await incoming.setVolume(master);
      } catch (_) {}

      unawaited(ResonateDiagnostics.record('repeat_self_committed', {
        'mode': 'dual',
        'songId': song.id,
        'activeEngine': _activeIsA ? 'A' : 'B',
        'playing': incoming.playing,
      }));
      return true;
    } catch (e, st) {
      debugPrint('repeat dual failed: $e');
      debugPrint('$st');
      try { await incoming.pause(); } catch (_) {}
      try { await incoming.setVolume(0.0); } catch (_) {}
      if (_repeatSelfGeneration == generation &&
          identical(outgoing, audioPlayer)) {
        try { await outgoing.setVolume(master); } catch (_) {}
      }
      return false;
    }
  }

  bool _repeatSelfTransitionCurrent(int generation) =>
      generation == _repeatSelfGeneration &&
      _repeatSelfHandoffInFlight &&
      effectiveCrossfadeEnabled &&
      _repeatMode == PlaybackRepeatMode.one &&
      _userWantsPlaying;

  Future<void> _abortRepeatSelfEngine(AudioPlayer incoming) async {
    try { await incoming.pause(); } catch (_) {}
    try { await incoming.setVolume(0.0); } catch (_) {}
    // The cancellation owner restores the outgoing gain only when no newer
    // transport command has taken ownership; stale work must not boost it.
  }

  Future<void> _recoverCancelledRepeatSelfEngine() async {
    final active = audioPlayer;
    final idle = inactivePlayer;
    try { await idle.pause(); } catch (_) {}
    try { await idle.setVolume(0.0); } catch (_) {}
    try {
      if (identical(active, audioPlayer)) {
        await active.setVolume(_effectiveCrossfadeMaster.clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  /// Soft loop: fade out → seek(0) → fade in on the *active* engine only.
  /// Avoids loading the same content:// URI on A and B (OEM hang / static).
  Future<void> _runRepeatSelfSoftLoop({
    required int loopMs,
    required int generation,
  }) async {
    final song = currentSong;
    if (!_repeatSelfTransitionCurrent(generation)) return;
    if (song == null) {
      _automaticCrossfadeInFlight = false;
      _repeatSelfHandoffInFlight = false;
      return;
    }
    final ms = loopMs.clamp(600, 4000);
    final master = _eqPreampScale.clamp(0.05, 1.0);
    final player = audioPlayer;
    unawaited(ResonateDiagnostics.record('repeat_self_ramp', {
      'mode': 'soft_single',
      'songId': song.id,
      'ms': ms,
      'engine': _activeIsA ? 'A' : 'B',
    }));
    try {
      // Keep inactive fully quiet so nothing bleeds.
      try {
        await inactivePlayer.setVolume(0.0);
      } catch (_) {}
      try {
        await inactivePlayer.pause();
      } catch (_) {}

      final from = player.volume.clamp(0.0, 1.0);
      await _fadePlayerVolume(player, from, 0.0, durationMs: ms ~/ 2);
      if (!_repeatSelfTransitionCurrent(generation)) return;
      if (!_userWantsPlaying) {
        unawaited(ResonateDiagnostics.record('repeat_self_cancel', {
          'reason': 'user_stopped',
          'songId': song.id,
        }));
        return;
      }
      try {
        await player.seek(Duration.zero);
      } catch (e) {
        debugPrint('soft loop seek: $e');
      }
      if (!_repeatSelfTransitionCurrent(generation)) return;
      currentPosition = Duration.zero;
      try {
        player.play();
      } catch (_) {}
      for (var i = 0; i < 10 && !player.playing && _userWantsPlaying; i++) {
        await Future<void>.delayed(Duration(milliseconds: 30 + i * 20));
        try {
          player.play();
        } catch (_) {}
      }
      if (!_repeatSelfTransitionCurrent(generation)) return;
      await _fadePlayerVolume(player, 0.0, master, durationMs: ms ~/ 2);
      if (!_repeatSelfTransitionCurrent(generation)) return;
      isPlaying = player.playing || _userWantsPlaying;
      _lastCompletionSongId = null;
      _publishServiceState();
      notifyListeners();
      unawaited(ResonateDiagnostics.record('repeat_self_committed', {
        'mode': 'soft_single',
        'songId': song.id,
        'activeEngine': _activeIsA ? 'A' : 'B',
        'playing': player.playing,
      }));
    } catch (e, st) {
      debugPrint('soft loop failed: $e');
      debugPrint('$st');
      // Do not restart or rewind after a user/mode cancellation.
      if (generation == _repeatSelfGeneration && _repeatSelfHandoffInFlight) {
        try {
          await player.seek(Duration.zero);
          if (_userWantsPlaying) {
            try { player.play(); } catch (_) {}
            try { await player.setVolume(master); } catch (_) {}
          }
        } catch (_) {}
        unawaited(ResonateDiagnostics.record('repeat_self_fallback', {
          'reason': 'soft_loop_error',
          'songId': song.id,
          'error': '$e',
        }));
      }
    } finally {
      // A stale loop must not clear state owned by a newer transition.
      if (generation == _repeatSelfGeneration) {
        _automaticCrossfadeInFlight = false;
        _crossfadeInProgress = false;
        _repeatSelfHandoffInFlight = false;
        _repeatSelfHandoffArmed = false;
        _repeatSelfTargetSongId = null;
      }
    }
  }

  Future<void> _runRepeatSelfHandoff() async {
    // Legacy entry — redirect to soft loop.
    final loopMs = _crossfadeDurationMs.clamp(800, 3500);
    await _runRepeatSelfSoftLoop(
      loopMs: loopMs,
      generation: _repeatSelfGeneration,
    );
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
      debugPrint('repeat self handoff failed: $e');
      debugPrint('$st');
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
    if (!effectiveCrossfadeEnabled || _crossfadePreloadInFlight || !canCrossfadeNext) return;
    final next = _crossfadeTargetSong;
    if (next == null || _preloadedNextSongId == next.id) return;

    // A preload is automatic work too. Capture ownership so a Mode change,
    // crossfade toggle, or manual transport cannot let a stale async preload
    // overwrite the idle engine after a newer command has taken ownership.
    final generation = _automaticTransitionGeneration;
    final transportEpoch = _userTransportEpoch;
    bool stillOwnsPreload() =>
        generation == _automaticTransitionGeneration &&
        transportEpoch == _userTransportEpoch &&
        effectiveCrossfadeEnabled &&
        _crossfadeTargetSong?.id == next.id;
    _crossfadePreloadInFlight = true;

    // DJ Mode: priority-warm analysis for current + next queue head.
    if (_djAnalysis != null &&
        (_djBeatAlignActive || _djTempoMatchActive)) {
      final cur = currentSong;
      if (cur != null) _djAnalysis!.scheduleAnalyze(cur);
      _djAnalysis!.scheduleAnalyze(next);
      final start = _queueIndex + 1;
      final end = (start + 4).clamp(0, _queue.length);
      for (var i = start; i < end; i++) {
        if (i != _crossfadeTargetIndex) _djAnalysis!.scheduleAnalyze(_queue[i]);
      }
    }

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
      if (!stillOwnsPreload()) return;
      try {
        await incoming.stop();
      } catch (_) {}
      if (!stillOwnsPreload()) return;
      await incoming.setVolume(0.0);
      if (!stillOwnsPreload()) return;
      await incoming.setAudioSource(AudioSource.uri(_audioUri(next.filePath), tag: next));
      if (!stillOwnsPreload()) return;

      unawaited(_enableEffects(incoming, incomingEq, incomingLoud));
      await incoming.setVolume(0.0);
      if (!stillOwnsPreload()) return;

      // Decode/warm muted. Re-check ownership after every delay before
      // issuing more commands to the shared player.
      try {
        incoming.play();
      } catch (_) {}
      for (var i = 0; i < 6 && !incoming.playing; i++) {
        await Future<void>.delayed(Duration(milliseconds: 30 + i * 15));
        if (!stillOwnsPreload()) return;
        try {
          await incoming.setVolume(0.0);
        } catch (_) {}
        if (!stillOwnsPreload()) return;
        if (i % 2 == 0) {
          try {
            incoming.play();
          } catch (_) {}
        }
      }
      if (!stillOwnsPreload()) return;
      try {
        await incoming.pause();
      } catch (_) {}
      if (!stillOwnsPreload()) return;
      try {
        await incoming.seek(Duration.zero);
      } catch (_) {}
      if (!stillOwnsPreload()) return;
      await incoming.setVolume(0.0);
      if (!stillOwnsPreload()) return;

      // Do not let a stale preload restore gain on an engine that has become
      // active for a newer transition.
      try {
        final targetOut = (outgoingVol ?? _volume).clamp(0.0, 1.0);
        if (identical(outgoing, audioPlayer) &&
            (outgoing.volume - targetOut).abs() > 0.02) {
          await outgoing.setVolume(targetOut);
        }
      } catch (_) {}
      if (!stillOwnsPreload()) return;

      _preloadedNextSongId = next.id;
      await ResonateDiagnostics.record('crossfade_preloaded', {
        'songId': next.id,
        'queueIndex': _crossfadeTargetIndex,
        'playing': incoming.playing,
        'repeatMode': _repeatMode.name,
        'outgoingVolume': outgoingVol,
      });
    } catch (e) {
      if (generation == _automaticTransitionGeneration &&
          transportEpoch == _userTransportEpoch) {
        if (_preloadedNextSongId == next.id) _preloadedNextSongId = null;
        debugPrint('crossfade preload failed: $e');
        await ResonateDiagnostics.record('crossfade_preload_failed', {
          'error': e.toString(),
          'songId': next.id,
        });
      }
    } finally {
      // A cancelled older preload must not clear the in-flight flag belonging
      // to a newer preload started after cancellation.
      if (generation == _automaticTransitionGeneration &&
          transportEpoch == _userTransportEpoch) {
        _crossfadePreloadInFlight = false;
      }
    }
  }

  Future<void> _runAutomaticCrossfade() async {
    // Do not even register automatic ownership if a user transport is queued.
    if (_transportInFlight || _loadingSource || _userTransportPending) {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
      _transitionArmedAt = null;
      return;
    }
    final generation = _authority.beginAutomatic('automatic_crossfade');
    final transitionMarker = _automaticTransitionGeneration + 1;
    final epoch = _userTransportEpoch;
    final fromIndex = _queueIndex;
    final fromSongId = currentSong?.id;
    if (_transportInFlight || _loadingSource || _userTransportPending) {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
      _transitionArmedAt = null;
      return;
    }
    try {
      final djActive = _djBeatAlignActive || _djTempoMatchActive || _djSfxActive;
      final plannedBias = _lastDjCrossfadeBiasMs;
      final xfMs = (djActive
              ? (_crossfadeDurationMs + plannedBias).clamp(500, 6500)
              : _crossfadeDurationMs)
          .toInt();
      // Position events can become discontinuous around backgrounding/audio
      // service resumes. Revalidate the actual remaining time here instead of
      // trusting the earlier position-stream trigger to still be current.
      final durationNow = audioPlayer.duration;
      final remainingNowMs = durationNow == null
          ? null
          : durationNow.inMilliseconds - audioPlayer.position.inMilliseconds;
      final startMarginMs = (1200 + (xfMs ~/ 10)).clamp(1500, 3000);
      final safeTriggerMs = (xfMs + startMarginMs).clamp(2000, 16000);
      // Background/route changes can briefly invalidate timing signals. Fail
      // closed when the active engine has no trustworthy duration/position,
      // and never start a transition outside the near-end window.
      if (durationNow == null ||
          durationNow <= Duration.zero ||
          remainingNowMs == null ||
          remainingNowMs > safeTriggerMs ||
          remainingNowMs < 1200) {
        _automaticCrossfadeInFlight = false;
        _crossfadeInProgress = false;
        _transitionArmedAt = null;
        await ResonateDiagnostics.record('crossfade_aborted_timing_revalidation', {
          'remainingMs': remainingNowMs,
          'safeTriggerMs': safeTriggerMs,
          'durationMs': durationNow?.inMilliseconds,
          'positionMs': audioPlayer.position.inMilliseconds,
          'engine': _activeIsA ? 'A' : 'B',
          'reason': durationNow == null || durationNow <= Duration.zero
              ? 'duration_unavailable'
              : remainingNowMs == null
                  ? 'position_unavailable'
                  : remainingNowMs > safeTriggerMs
                      ? 'not_near_end'
                      : 'too_late',
          'outgoingSongId': fromSongId,
          'queueIndex': fromIndex,
        });
        return;
      }
      final timeout =
          Duration(milliseconds: (xfMs + 12000).clamp(12000, 30000));
      final ok = await _performTrueCrossfade(
        milliseconds: xfMs,
        fadeType: _crossfadeFadeType,
        generation: generation,
      ).timeout(timeout, onTimeout: () {
        debugPrint('automatic crossfade timed out');
        // Future.timeout does not cancel the underlying Future. Invalidate its
        // ownership before fallback/cleanup so a delayed native player call
        // cannot later commit the handoff or restore stale gain.
        if (_userTransportEpoch == epoch &&
            _automaticTransitionGeneration == transitionMarker) {
          _automaticTransitionGeneration++;
          _preloadedNextSongId = null;
          _crossfadePreloadInFlight = false;
          _automaticCrossfadeInFlight = false;
          _crossfadeInProgress = false;
          _transitionArmedAt = null;
          unawaited(ResonateDiagnostics.record('crossfade_timeout_invalidated', {
            'transitionGeneration': transitionMarker,
            'currentGeneration': _automaticTransitionGeneration,
            'userTransportEpoch': _userTransportEpoch,
            'outgoingSongId': fromSongId,
            'queueIndex': fromIndex,
            'timeoutMs': timeout.inMilliseconds,
          }));
        }
        return false;
      });
      if (ok) return;
      if (_userTransportEpoch != epoch ||
          _automaticTransitionGeneration != transitionMarker ||
          _authority.isStale(generation) ||
          currentSong?.id != fromSongId ||
          _queueIndex != fromIndex) {
        await ResonateDiagnostics.record('crossfade_fallback_skipped_already_advanced', {
          'preempted': _userTransportEpoch != epoch,
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
      if (_userTransportEpoch != epoch ||
          _automaticTransitionGeneration != transitionMarker ||
          _authority.isStale(generation) ||
          currentSong?.id != fromSongId ||
          _queueIndex != fromIndex) {
        await ResonateDiagnostics.record('crossfade_preempted_by_user', {
          'stage': 'fallback_soft',
          'fromSongId': fromSongId,
        });
        return;
      }
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
      if (_userTransportEpoch == epoch &&
          _automaticTransitionGeneration == transitionMarker &&
          !_authority.isStale(generation) &&
          currentSong?.id == fromSongId &&
          _queueIndex == fromIndex) {
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
      if (_automaticTransitionGeneration == transitionMarker) {
        _automaticCrossfadeInFlight = false;
        _crossfadeInProgress = false;
      }
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

      if (_crossfadeInProgress ||
          _automaticCrossfadeInFlight ||
          _repeatSelfHandoffInFlight) {
        unawaited(ResonateDiagnostics.record('end_of_track_watchdog_crossfade_stuck', {
          'songId': currentSong?.id,
          'crossfadeInProgress': _crossfadeInProgress,
          'automaticCrossfadeInFlight': _automaticCrossfadeInFlight,
          'repeatSelfInFlight': _repeatSelfHandoffInFlight,
          'graceMs': graceMs,
          'activeEngine': _activeIsA ? 'A' : 'B',
        }));
        // Invalidate any in-flight transition before the watchdog takes
        // ownership. Its async cleanup will see the new generation and will
        // not mutate the watchdog's engine state.
        _automaticTransitionGeneration++;
        _crossfadeInProgress = false;
        _automaticCrossfadeInFlight = false;
        _completionObservedDuringCrossfade = false;
        _repeatSelfHandoffInFlight = false;
        _repeatSelfHandoffArmed = false;
        _repeatSelfTargetSongId = null;
        // Silence *inactive* only — never stop the active engine (was killing B
        // after a crossfade commit when B was active → silence / static).
        unawaited(() async {
          try {
            await inactivePlayer.pause();
          } catch (_) {}
          try {
            await inactivePlayer.setVolume(0.0);
          } catch (_) {}
          try {
            await audioPlayer.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
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

    // Repeat-one already owns the next start (self handoff / seek 0).
    if (_repeatMode == PlaybackRepeatMode.one) {
      _completionObservedDuringCrossfade = false;
      try {
        final vol = _effectiveCrossfadeMaster.clamp(0.05, 1.0);
        if (audioPlayer.volume < vol * 0.85) {
          await audioPlayer.setVolume(vol);
        }
        if (_userWantsPlaying && !audioPlayer.playing) {
          try {
            audioPlayer.play();
          } catch (_) {}
        }
        isPlaying = _userWantsPlaying && audioPlayer.playing;
        _publishServiceState();
        notifyListeners();
      } catch (_) {}
      return;
    }

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
          await _applyActiveMasterVolume();
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
      _podcastSession.onCompleted(currentPosition);
    _audiobookSession.onCompleted(currentPosition);
      await _finishHistoryEvent(completed: true);
      if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
        // Only defer while soft-loop is *actually* running (not stuck flags).
        if (_repeatSelfHandoffInFlight) {
          await ResonateDiagnostics.record('completion_advance_result', {
            'result': 'repeat_deferred_to_self_handoff',
            'songId': currentSong?.id,
          });
          return;
        }
        _lastCompletionSongId = null;
        currentPosition = Duration.zero;
        // Do not resume mid-track after a failed loop — clear saved offset.
        if (_resumeSongId == currentSong?.id) {
          _resumePositionMs = 0;
          _resumeSongId = null;
        }
        if (currentSong != null) {
          _resumeStore.clearSong(currentSong!.id);
        }
        try {
          await audioPlayer.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
        } catch (_) {}
        await audioPlayer.seek(Duration.zero);
        try {
          audioPlayer.play();
        } catch (_) {}
        isPlaying = true;
        _userWantsPlaying = true;
        await _startHistoryEvent(currentSong!);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('completion_advance_result', {
          'result': 'repeated',
          'songId': currentSong?.id,
        });
        return;
      }
      // A queue item can fail to load (for example a stale MediaStore URI).
      // Do not strand playback on that item while later queue entries are valid.
      // Track IDs rather than indices because _playSongInternal may reorder the
      // queue when shuffle is enabled.
      final attemptedSongIds = <String>{fromSongId};
      var scanFromIndex = fromIndex;
      var skippedFailedTracks = 0;
      for (var attempt = 0; attempt < _queue.length; attempt++) {
        if (_queue.isEmpty) break;
        var candidateIndex = -1;

        // Prefer the next item in queue order. Repeat All alone may wrap.
        for (var i = (scanFromIndex + 1).clamp(0, _queue.length).toInt(); i < _queue.length; i++) {
          if (!attemptedSongIds.contains(_queue[i].id)) {
            candidateIndex = i;
            break;
          }
        }
        if (candidateIndex < 0 && _repeatMode == PlaybackRepeatMode.all) {
          for (var i = 0; i < _queue.length; i++) {
            if (!attemptedSongIds.contains(_queue[i].id)) {
              candidateIndex = i;
              break;
            }
          }
          // If every other item failed, give the just-completed item one
          // final attempt. The bounded outer loop prevents endless retries.
          if (candidateIndex < 0 && attempt == _queue.length - 1) {
            candidateIndex = _queue.indexWhere((s) => s.id == fromSongId);
          }
        }
        if (candidateIndex < 0) break;

        final candidate = _queue[candidateIndex];
        attemptedSongIds.add(candidate.id);
        _userWantsPlaying = true;
        final ok = await _playSongInternal(
          candidate,
          queue: _queue,
          startIndex: candidateIndex,
          playbackIntentToken: intentToken,
        );

        if (ok) {
          // Guarantee an audible start after auto-advance (no user gesture).
          if (!audioPlayer.playing && _userWantsPlaying) {
            try {
              final session = await AudioSession.instance;
              await session.setActive(true);
            } catch (_) {}
            try {
              await audioPlayer.seek(Duration.zero);
            } catch (_) {}
            try {
              audioPlayer.play();
            } catch (_) {}
            isPlaying = audioPlayer.playing || _userWantsPlaying;
            _publishServiceState();
            notifyListeners();
          }
          await ResonateDiagnostics.record('completion_advance_result', {
            'result': skippedFailedTracks > 0
                ? 'advanced_after_failed_tracks'
                : (candidateIndex <= fromIndex &&
                        _repeatMode == PlaybackRepeatMode.all
                    ? 'wrapped'
                    : 'advanced'),
            'fromSongId': fromSongId,
            'toSongId': currentSong?.id,
            'queueIndex': _queueIndex,
            'failedTrackCount': skippedFailedTracks,
            'playing': audioPlayer.playing,
          });
          return;
        }

        skippedFailedTracks++;
        scanFromIndex = _queueIndex;
        await ResonateDiagnostics.record('completion_advance_result', {
          'result': 'skipped_unplayable_track',
          'fromSongId': fromSongId,
          'failedSongId': candidate.id,
          'failedTrackCount': skippedFailedTracks,
          'queueIndex': _queueIndex,
        });
        // _playSongInternal marks user intent false on failure; auto-advance
        // still owns the transport and may try the next distinct queue item.
        _userWantsPlaying = true;
      }
      isPlaying = false;
      _userWantsPlaying = false;
      currentPosition = currentDuration ?? currentPosition;
      await _persistQueue();
      _publishServiceState();
      notifyListeners();
      await ResonateDiagnostics.record('completion_advance_result', {
        'result': skippedFailedTracks > 0
            ? 'queue_exhausted_after_failed_tracks'
            : 'queue_exhausted',
        'fromSongId': fromSongId,
        'queueIndex': _queueIndex,
        'failedTrackCount': skippedFailedTracks,
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

  Future<T> _serializePlayback<T>(
    Future<T> Function() operation, {
    required String command,
    required String source,
    bool userInitiated = false,
    int? intentToken,
    Future<T> Function()? onSuperseded,
  }) async {
    // Mark transport intent synchronously, before the diagnostic write or
    // coordinator await. Otherwise a near-end position callback can launch a
    // fresh automatic crossfade in the gap before a tapped track starts.
    final transportPriority = userInitiated && const {
      'toggle', 'pause', 'stop', 'seek', 'play', 'next', 'previous',
    }.contains(command);
    if (transportPriority) _pendingUserTransportCount++;
    try {
      final effectiveIntent = intentToken ??
          (userInitiated ? _playbackIntentGate.issue() : _playbackIntentGate.currentToken);
      if (userInitiated) {
        _authority.markExternalUserCommand(source, command);
        unawaited(ResonateDiagnostics.record('playback_command_accepted', {
          'command': command,
          'source': source,
          'intentToken': effectiveIntent,
        }));
      }
      await ResonateDiagnostics.record('playback_operation_queued', {
        'command': command,
        'source': source,
        'userInitiated': userInitiated,
        'intentToken': effectiveIntent,
        'lane': transportPriority ? 'transport_priority' : 'source_serialized',
      });
      if (transportPriority) {
        return await _playbackCoordinator.runTransport(operation);
      }
      return await _playbackCoordinator.runSourceMutation(
        operation,
        command: command,
        supersedePending: userInitiated &&
            const {'play', 'next', 'previous'}.contains(command),
        onSuperseded: onSuperseded,
      );
    } finally {
      if (transportPriority && _pendingUserTransportCount > 0) {
        _pendingUserTransportCount--;
      }
    }
  }

  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0, bool resumeIfPossible = false, int? resumeAtMs}) {
    final intentToken = _playbackIntentGate.issue();
    final wasXf = _crossfadeInProgress || _automaticCrossfadeInFlight;
    _cancelAutomaticPlaybackWork();
    if (wasXf) {
      unawaited(ResonateDiagnostics.record('crossfade_preempted_by_user', {
        'stage': 'play_song',
        'requestedSongId': song.id,
        'wasSongId': currentSong?.id,
        'queueIndex': _queueIndex,
      }));
    }
    _lastCompletionSongId = null;
    if (resumeAtMs != null && resumeAtMs > 1500) {
      _resumeSongId = song.id;
      _resumePositionMs = resumeAtMs;
      _resumeStore.bySongId[song.id] = resumeAtMs;
    } else if (resumeIfPossible) {
      final mapped = resumePositionFor(song.id);
      if (mapped != null) {
        _resumeSongId = song.id;
        _resumePositionMs = mapped;
      }
    }
    // Precise resume is a Mode playback policy. Normal/routine modes keep
    // the existing start-from-zero behavior; content/session modes that
    // explicitly require precise resume may restore the saved position.
    final shouldResume = _modePreciseResume &&
        resumeIfPossible &&
        _resumeSongId == song.id &&
        _resumePositionMs > 1500;
    return _serializePlayback(
      () => _playSongInternal(song, queue: queue, startIndex: startIndex, resume: shouldResume, playbackIntentToken: intentToken),
      command: 'play', source: 'normal_player', userInitiated: true, intentToken: intentToken,
      onSuperseded: () async => false,
    );
  }

  Future<bool> _playSongInternal(Song song, {List<Song>? queue, int startIndex = 0, bool resume = false, int? playbackIntentToken}) async {
    await _visibility.load();
    if (_visibility.isRestricted &&
        !_visibility.isVisible(song.id) &&
        !(_modes?.isModeFolderSong(song.id) ?? false)) {
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

      // User play always owns Engine A. Kill any dying crossfade on B first.
      _ensureEngineA(reason: 'play_song');
      try {
        await _playerB.pause();
      } catch (_) {}
      try {
        await _playerB.setVolume(0.0);
      } catch (_) {}
      try {
        await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
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

      final nextQueue = effectiveShuffleEnabled && normalized.length > 1
          ? () {
              final selected = normalized[selectedIndex];
              final upcoming = <Song>[...normalized]..removeAt(selectedIndex)..shuffle(math.Random());
              return <Song>[selected, ...upcoming];
            }()
          : normalized;
      final nextIndex = effectiveShuffleEnabled && normalized.length > 1 ? 0 : selectedIndex;

      // Pin UI to the song we intend to play before any native load races.
      currentSong = selectedSong;
      unawaited(_refreshTrackLevelingFor(currentSong));
      _podcastSession.onSongStarted(
        modes: _modes,
        song: selectedSong,
        resumePosition: resume ? Duration(milliseconds: _resumePositionMs) : null,
      );
      _audiobookSession.onSongStarted(
        modes: _modes,
        song: selectedSong,
        resumePosition: resume ? Duration(milliseconds: _resumePositionMs) : null,
      );
      _modes?.onPlaybackStarted(selectedSong, position: resume ? Duration(milliseconds: _resumePositionMs) : Duration.zero);
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

      final loopMode = (!effectiveCrossfadeEnabled)
          ? switch (_repeatMode) {
              PlaybackRepeatMode.one => LoopMode.one,
              // Repeat-all advances the app queue; native LoopMode.all on a single
            // source would repeat the current track instead of advancing.
            PlaybackRepeatMode.all => LoopMode.off,
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
      _gaplessWindow.active = false;
      _gaplessWindow.songIds = const [];
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
            _gaplessWindow.active = true;
            _gaplessWindow.start = start;
            _gaplessWindow.songIds = window.map((s) => s.id).toList();
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
          _gaplessWindow.active = false;
          _gaplessWindow.songIds = const [];
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
      unawaited(_refreshTrackLevelingFor(currentSong));
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

      await timed('setVolume', target.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0)), ms: 2000);
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
      unawaited(_refreshTrackLevelingFor(currentSong));
    }
  }

  Future<void> _startHistoryEvent(Song song) async {
    await _historySession.enqueue(() async {
      if (_historySession.activeEvent?.songId == song.id) return;
      final event = ListeningEvent(id: '${DateTime.now().microsecondsSinceEpoch}_${song.id}', songId: song.id, previousSongId: _queueIndex > 0 ? _queue[_queueIndex - 1].id : null, startedAt: DateTime.now(), durationPlayedMs: currentPosition.inMilliseconds, songDurationMs: song.duration.inMilliseconds, completionRatio: 0, completed: false, skipped: false);
      _historySession.activeEvent = event; _historySession.positionMs = currentPosition.inMilliseconds; _resumePositionMs = currentPosition.inMilliseconds; _resumeSongId = song.id;
      try { final inserted = await _database.insertListeningEvent(event); final playCount = await _database.updateSongPlayCount(song.id); if (inserted < 0 || playCount < 0) { unawaited(ResonateDiagnostics.record('listening_history_start_failed', {'songId': song.id, 'insertResult': inserted, 'playCountResult': playCount})); } } catch (e, stack) { debugPrint('Listening history start failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_start_failed', {'songId': song.id, 'error': e.toString(), 'stack': stack.toString()})); }
    });
  }

  Future<void> _finishHistoryEvent({bool completed = false}) async {
    await _historySession.enqueue(() async {
      final event = _historySession.activeEvent; if (event == null) return;
      final total = event.songDurationMs > 0 ? event.songDurationMs : (currentDuration?.inMilliseconds ?? 0); final position = _historySession.positionMs.clamp(0, total > 0 ? total : 1).toInt(); final ratio = total <= 0 ? 0.0 : (position / total).clamp(0.0, 1.0).toDouble(); final wasCompleted = completed || ratio >= .90;
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
            score: _lastDjTransitionScore,
            confidence: _lastDjTransitionConfidence,
            risks: _lastDjTransitionRisks,
            transitionDurationMs: _lastDjTransitionDurationMs,
            recoveryAttempts: _lastDjRecoveryAttempts,
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

      _historySession.activeEvent = null; _historySession.positionMs = 0;
      if (wasCompleted) { if (currentSong != null) { _resumeStore.clearSong(currentSong!.id); } else { _resumePositionMs = 0; _resumeSongId = null; } unawaited(_resumeStore.persist()); } else { _persistResumePosition(force: true); }
      try { final updatedRows = await _database.updateListeningEvent(updated); if (updatedRows < 0 || updatedRows == 0) { unawaited(ResonateDiagnostics.record('listening_history_finish_failed', {'songId': event.songId, 'eventId': event.id, 'updateResult': updatedRows})); } } catch (e, stack) { debugPrint('Listening history finish failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_finish_failed', {'songId': event.songId, 'error': e.toString(), 'stack': stack.toString()})); }
    });
  }

  Future<bool> enqueueSongs(List<Song> songs) async { await _visibility.load(); final additions = songs.where((s) => _visibility.isVisible(s.id) && s.filePath.trim().isNotEmpty && !_queue.any((q) => q.id == s.id)).toList(); if (additions.isEmpty) return false; if (effectiveShuffleEnabled && additions.length > 1) additions.shuffle(math.Random()); _queue.addAll(additions); await _persistQueue(); notifyListeners(); return true; }
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
  DjTransitionKind? _djTransitionKindFromName(String? name) {
    if (name == null) return null;
    for (final kind in DjTransitionKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// Snap planned SFX delay onto a nearby outgoing beat during the fade window.
  Duration _snapSfxDelayToPhrase({
    required Duration planned,
    required int fadeMs,
    DjTrackProfile? outgoingProfile,
  }) {
    final ideal = planned.inMilliseconds.clamp(0, fadeMs);
    final beats = outgoingProfile?.beatGrid.beatMs ?? const <int>[];
    if (beats.length < 4 || fadeMs < 400) {
      return Duration(milliseconds: ideal);
    }
    int posMs = 0;
    try {
      posMs = audioPlayer.position.inMilliseconds;
    } catch (_) {}
    var best = ideal;
    var bestDist = 1 << 30;
    for (final b in beats) {
      final rel = b - posMs;
      if (rel < 120 || rel > fadeMs - 80) continue;
      final d = (rel - ideal).abs();
      if (d < bestDist) {
        bestDist = d;
        best = rel;
      }
    }
    return Duration(milliseconds: best.clamp(100, fadeMs - 60));
  }

  Future<void> _engageDjTransitionSfx({
    double energyScore = 0.5,
    DjTransitionKind? transitionKind,
    Duration delay = Duration.zero,
    DjTrackProfile? outgoingProfile,
  }) async {
    if (!_djSfxActive) return;
    try {
      final profile = outgoingProfile;
      final beatMs = profile?.beatGrid.beatMs ?? const <int>[];
      final sections = profile?.sections ?? const <DjSection>[];
      if (delay > Duration.zero) {
        // Schedule without blocking crossfade start. Set _djSfxEngaged only
        // after the rack actually applies FX so _tickDjClubFxSweep runs for
        // the remainder of the fade. restore() bumps delayed generation so a
        // cancelled schedule cannot engage late.
        unawaited(() async {
          try {
            await _djSfxRack.engageDelayed(
              delay: delay,
              energyScore: energyScore,
              equalizerA: _equalizerA,
              equalizerB: _equalizerB,
              outgoing: audioPlayer,
              outgoingUri: currentSong?.filePath,
              beatMs: beatMs,
              sections: sections,
              transitionKind: transitionKind,
              aggressiveness: _djPolicy.aggressiveness,
            );
            if (_djSfxRack.engaged && _djSfxActive) {
              _djSfxEngaged = true;
              await ResonateDiagnostics.record('dj_transition_sfx', {
                'action': 'engage_after_delay',
                'delayMs': delay.inMilliseconds,
                'energyScore': energyScore,
                'preset': _djSfxRack.presetName,
              });
            }
          } catch (e) {
            debugPrint('DJ transition SFX delayed engage: $e');
          }
        }());
        await ResonateDiagnostics.record('dj_transition_sfx', {
          'action': 'scheduled',
          'delayMs': delay.inMilliseconds,
          'energyScore': energyScore,
        });
      } else {
        await _djSfxRack.engage(
          energyScore: energyScore,
          equalizerA: _equalizerA,
          equalizerB: _equalizerB,
          outgoing: audioPlayer,
          outgoingUri: currentSong?.filePath,
          beatMs: beatMs,
          sections: sections,
          transitionKind: transitionKind,
          aggressiveness: _djPolicy.aggressiveness,
        );
        _djSfxEngaged = true;
        await ResonateDiagnostics.record('dj_transition_sfx', {
          'action': 'engage',
          'delayMs': 0,
          'energyScore': energyScore,
          'preset': _djSfxRack.presetName,
        });
      }
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
      outgoing: audioPlayer,
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
    _activeDjExecutionPlan = null;
    if ((!_djHandoffsLive) || _djAnalysis == null) {
      return;
    }
    if (outgoingSong == null) return;
    try {
      final profileA = await _djAnalysis!.getProfile(outgoingSong.id);
      final profileB = await _djAnalysis!.getProfile(incomingSong.id);
      if (profileA != null && profileB != null) {
        // Autonomous layer: the musical brain proposes valid candidates;
        // local learning softly reranks them without ever removing fallback.
        final learnedCandidate = await _djAutopilotPlanner.choose(
          outgoing: profileA,
          incoming: profileB,
          outgoingPositionMs: outgoing.position.inMilliseconds,
          preferredDurationMs: _crossfadeDurationMs,
          maxDurationMs: 6500,
          policy: _djPolicy,
        );
        final v2 = _djEngine.execution.plan(
          outgoing: profileA,
          incoming: profileB,
          candidate: learnedCandidate,
          policy: _djPolicy,
        );
        if (!v2.fallback) {
          await _applyV2DjHandoff(
            outgoing: outgoing,
            incoming: incoming,
            outgoingSong: outgoingSong,
            incomingSong: incomingSong,
            profileA: profileA,
            profileB: profileB,
            plan: v2,
          );
          _activeDjExecutionPlan = v2;
          return;
        }
        await ResonateDiagnostics.recordDj(stage: 'v2_brain', outcome: 'fallback', reason: v2.reason, songId: incomingSong.id, extra: {'kind': v2.candidate.kind.name, 'score': v2.candidate.score});
      }

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
                maxRelativeDelta: stretch != null ? 0.22 : 0.09,
              )
            : computeBeatAlignedSeekMs(
                bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
                beatOffsetMsA: beatOffsetA,
                bpmB: effectiveBpmB,
                beatOffsetMsB: beatOffsetB,
                outgoingPositionMs: posMs,
                maxRelativeDelta: stretch != null ? 0.22 : 0.09,
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
      _lastDjTransitionScore = null;
      _lastDjTransitionConfidence = math.min(plan.confidenceA, plan.confidenceB);
      _lastDjTransitionRisks = const <String>[];
      _lastDjTransitionDurationMs = null;
      _lastDjRecoveryAttempts = 0;
      notifyListeners(); // dj transition chip
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

  Future<void> _applyV2DjHandoff({
    required AudioPlayer outgoing,
    required AudioPlayer incoming,
    required Song outgoingSong,
    required Song incomingSong,
    required DjTrackProfile profileA,
    required DjTrackProfile profileB,
    required DjExecutionPlan plan,
  }) async {
    final candidate = plan.candidate;
    _lastDjCrossfadeBiasMs = 0;
    _lastDjEnergyScore = candidate.scores['energy'] ?? 0.5;
    _lastDjBassDuckNeeded = candidate.risks.contains(DjRiskType.bassCollision);

    // The V2 execution planner is now the source of truth for transition
    // timing. The existing A/B crossfade loop remains the actual audio executor.
    // This deliberately keeps execution engine-neutral: if a step is unknown,
    // ordinary crossfade behavior remains the safe fallback.
    for (final step in plan.steps) {
      if (step.action == 'extend_crossfade') {
        final requested = (step.parameters['durationMs'] as num?)?.toInt();
        if (requested != null) {
          _lastDjCrossfadeBiasMs =
              (requested - candidate.durationMs).clamp(-4000, 8000).toInt();
        }
      }
    }

    final incomingDuration = incoming.duration ?? incomingSong.duration;
    final seekMs = candidate.incomingStartMs
        .clamp(0, incomingDuration.inMilliseconds)
        .toInt();
    await incoming.seek(Duration(milliseconds: seekMs));

    await ResonateDiagnostics.recordDj(
      stage: 'v2_execution',
      outcome: 'prepared',
      reason: 'timeline_mapped_to_ab',
      songId: incomingSong.id,
      extra: {
        'kind': candidate.kind.name,
        'incomingStartMs': seekMs,
        'durationMs': candidate.durationMs,
        'crossfadeBiasMs': _lastDjCrossfadeBiasMs,
        'steps': plan.steps.map((step) => {
          'action': step.action,
          'atMs': step.atMs,
          'parameters': step.parameters,
        }).toList(),
      },
    );

    var tempoApplied = false;
    _lastDjIncomingBeatMs = profileB.beatGrid.beatMs;
    _lastDjIncomingBpm = profileB.beatGrid.bpm;
    _djBeatCorrectionAttempts = 0;
    if (_djTempoMatchActive &&
        profileA.beatGrid.bpm != null &&
        profileB.beatGrid.bpm != null) {
      final stretch = computeTempoStretch(
        bpmA: profileA.beatGrid.bpm!,
        bpmB: profileB.beatGrid.bpm!,
        maxStretchPercent: _djMaxStretchPercent,
      );
      if (stretch != null) {
        await outgoing.setSpeed(stretch.speedOutgoing);
        await incoming.setSpeed(stretch.speedIncoming);
        _djStretchSpeedOut = stretch.speedOutgoing;
        _djStretchSpeedIn = stretch.speedIncoming;
        tempoApplied = true;
      }
    }

    _lastDjHandoffAt = DateTime.now();
    _lastDjFromId = outgoingSong.id;
    _lastDjToId = incomingSong.id;
    _lastDjStrategy = candidate.kind.name;
    _lastDjTransitionScore = candidate.score;
    _lastDjTransitionConfidence = candidate.confidence;
    _lastDjTransitionRisks = candidate.risks.map((r) => r.name).toList();
    _lastDjTransitionDurationMs = candidate.durationMs;
    _lastDjRecoveryAttempts = 0;
    notifyListeners(); // dj transition chip
    await ResonateDiagnostics.recordDj(
      stage: 'v2_handoff',
      outcome: 'applied',
      reason: plan.reason,
      songId: incomingSong.id,
      extra: {
        'kind': candidate.kind.name,
        'score': candidate.score,
        'confidence': candidate.confidence,
        'seekMs': seekMs,
        'tempoApplied': tempoApplied,
        'risks': candidate.risks.map((r) => r.name).toList(),
        'scores': candidate.scores,
      },
    );
  }

  Future<bool> _performTrueCrossfade({required int milliseconds, String fadeType = 'linear', required int generation, int? playbackIntentToken}) async {
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    final transitionGeneration = ++_automaticTransitionGeneration;
    final transportEpoch = _userTransportEpoch;
    final bassDuckOriginal = <int, double>{};
    if (!_playbackIntentGate.isCurrent(intentToken)) return false;
    if (!canCrossfadeNext || currentSong == null || !audioPlayer.playing) return false;
    final nextIndex = _crossfadeTargetIndex;
    final nextSong = _crossfadeTargetSong;
    if (nextSong == null || nextSong.filePath.trim().isEmpty) return false;
    _crossfadeInProgress = true; _transitionArmedAt = DateTime.now(); final outgoing = audioPlayer; final outgoingSong = currentSong; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _effectiveCrossfadeMaster.clamp(0.05, 1.0).toDouble();
    try {
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      await outgoing.setLoopMode(LoopMode.off);

      // Gapless concatenating source fights dual-engine crossfade (index jumps,
      // double-completion). Flatten outgoing to a single URI at current position.
      if (_gaplessWindow.active && outgoingSong != null) {
        final holdPos = outgoing.position;
        final wasPlaying = outgoing.playing;
        try {
          await _loadSingle(
            outgoing,
            equalizer,
            loudnessEnhancer,
            outgoingSong,
            start: false,
          );
          try {
            await outgoing.seek(holdPos);
          } catch (_) {}
          try {
            await outgoing.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
          } catch (_) {}
          if (wasPlaying) {
            try {
              outgoing.play();
            } catch (_) {}
          }
          unawaited(ResonateDiagnostics.record('crossfade_gapless_flattened', {
            'songId': outgoingSong.id,
            'positionMs': holdPos.inMilliseconds,
          }));
        } catch (e) {
          debugPrint('gapless flatten for crossfade: $e');
        }
        _gaplessWindow.active = false;
        _gaplessWindow.songIds = const [];
      }

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
      // Hard-mute before play — prevents a one-frame blast / static on some OEMs.
      try {
        await outgoing.setVolume(outgoing.volume.clamp(0.0, 1.0));
      } catch (_) {}
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
      final djExecution = _activeDjExecutionPlan;
      final bassDuckNeeded = _lastDjBassDuckNeeded;
      if (_automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) {
        try { await incoming.stop(); } catch (_) {}
        await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
        return false;
      }
      if (bassDuckNeeded) {
        final capturedBassDuck = await _audioEffectsController.duckBassForTransition(
          equalizer: incomingEq,
          attenuationDb: 4.0,
        );
        bassDuckOriginal
          ..clear()
          ..addAll(capturedBassDuck);
        unawaited(ResonateDiagnostics.record('dj_bass_duck', {
          'action': 'engage',
          'attenuationDb': 4.0,
          'bands': bassDuckOriginal.keys.toList(),
          'songId': nextSong.id,
        }));
      }
      final sfxStep = djExecution == null ? null : djExecution.steps.cast<DjExecutionStep?>().firstWhere(
        (step) => step?.action == 'trigger_sfx',
        orElse: () => null,
      );
      final plannedSfxMs = sfxStep?.atMs ?? 0;
      final fadeWindowMs = milliseconds.clamp(500, 12000);
      DjTrackProfile? outProfile;
      try {
        final id = outgoingSong?.id;
        if (id != null && _djAnalysis != null) {
          outProfile = await _djAnalysis!.getProfile(id);
        }
      } catch (_) {}
      await _engageDjTransitionSfx(
        energyScore: _lastDjEnergyScore,
        transitionKind: _djTransitionKindFromName(_lastDjStrategy),
        delay: _snapSfxDelayToPhrase(
          planned: Duration(milliseconds: plannedSfxMs),
          fadeMs: fadeWindowMs,
          outgoingProfile: outProfile,
        ),
        outgoingProfile: outProfile,
      );

      // A user can select a different Library track while preparation awaits
      // analysis/SFX work. Re-check ownership immediately before starting B;
      // the fade-loop guard alone is too late because B may already be audible.
      bool transitionWasPreempted() =>
          _userTransportEpoch != transportEpoch ||
          _automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken);

      if (transitionWasPreempted()) {
        // A newer transport now owns both reusable engines and their effects.
        // Do not stop/mute either engine here: the incoming engine may already
        // have been repurposed to play the user's newly selected track.
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'before_incoming_start',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }

      // Fire-and-poll play on B — await play() can hang and block auto-next forever.
      try {
        incoming.play();
      } catch (_) {}
      var incomingStarted = incoming.playing;
      for (var i = 0; i < 25 && !incomingStarted; i++) {
        // Do not retry play/seek on B after a manual transport supersedes us.
        if (transitionWasPreempted()) {
          // Engine instances are shared with manual playback. The new
          // transport owns cleanup; stale crossfade work must not touch them.
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'incoming_start_poll',
            'preempted': _userTransportEpoch != transportEpoch,
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }
        if (incoming.playing) {
          incomingStarted = true;
          break;
        }
        if (i == 5 || i == 12 || i == 18) {
          try { await incoming.seek(Duration.zero); } catch (_) {}
          if (!transitionWasPreempted()) {
            try { incoming.play(); } catch (_) {}
          }
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
      // The selected track may have changed during the settle delay. Never let
      // this stale transition issue play/volume commands against a reused engine.
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'incoming_start_settle',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      try { if (!incoming.playing) incoming.play(); } catch (_) {}
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'incoming_start_settle_play',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      // Start from the *current* outgoing level — never boost to master mid-track
      // (that was the pre-crossfade "bump" on some files).
      double startOut = master;
      try {
        startOut = outgoing.volume.clamp(0.0, 1.0);
      } catch (_) {}
      if (startOut > master) startOut = master;
      // Cap base to master so we never fade from above user volume.
      // Preserve intentional silence/ducking; a near-zero level is not permission to jump to master.
      final base = startOut;
      try {
        await outgoing.setVolume(base);
      } catch (_) {}
      // Volume writes are asynchronous; the user may have selected another
      // track while the outgoing engine was applying its level.
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'initial_outgoing_volume',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      await incoming.setVolume(0.0);
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'initial_incoming_volume',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }

      // DJ Mode: long fades (8–12s) + stretch/SFX feel mushy and raise static risk.
      final djActive = _djBeatAlignActive || _djTempoMatchActive || _djSfxActive;
      final maxMs = djActive ? 6500 : 12000;
      final plannedMs =
          (milliseconds + _lastDjCrossfadeBiasMs).clamp(500, maxMs).toInt();
      if (_lastDjCrossfadeBiasMs != 0 || (djActive && milliseconds > maxMs)) {
        unawaited(ResonateDiagnostics.record('crossfade_energy_bridge', {
          'biasMs': _lastDjCrossfadeBiasMs,
          'baseMs': milliseconds,
          'plannedMs': plannedMs,
          'djCapped': djActive && milliseconds > maxMs,
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
      // Snapshot analysis for this transition. A stale A/B loop must never
      // read a newer transition's beat grid while it is unwinding.
      final runtimeBeatMs = List<int>.from(_lastDjIncomingBeatMs);
      final runtimeBpm = _lastDjIncomingBpm;
      final gentle = Platform.isAndroid;
      final stepMs = gentle ? 36 : 24;
      final fadeStartedAt = DateTime.now();
      var lastOut = base;
      var lastIncomingPositionMs = incoming.position.inMilliseconds;
      var lastIncomingProgressAt = fadeStartedAt;
      var incomingRecoveryAttempts = 0;
      var monitorTick = 0;
      while (true) {
        if (_userTransportEpoch != transportEpoch ||
            _automaticTransitionGeneration != transitionGeneration ||
            _authority.isStale(generation) ||
            !_playbackIntentGate.isCurrent(intentToken)) {
          // Do not issue engine/effect commands after ownership changes.
          // The replacement transport may already be using either A or B.
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'fade',
            'preempted': _userTransportEpoch != transportEpoch,
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
        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);
        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);
        final outGain = math.cos(outT * (math.pi / 2.0));
        final inGain = math.sin(inT * (math.pi / 2.0));
        // If focus is lost mid-fade, scale both engines down together. If focus
        // returns, _unduckAfterInterruption defers restoration until this fade ends.
        final frameMaster = _effectiveCrossfadeMaster.clamp(0.05, 1.0).toDouble();
        final gainScale = (frameMaster / master).clamp(0.0, 1.0);
        final outVol = (base * outGain * gainScale).clamp(0.0, 1.0);
        final inVol = (frameMaster * inGain).clamp(0.0, 1.0);
        lastOut = outVol;
        final stepStarted = DateTime.now();
        try {
          // Parallel volume writes so outgoing does not stall waiting on incoming.
          await Future.wait([
            outgoing.setVolume(outVol),
            incoming.setVolume(inVol),
          ]);
        } catch (_) {}

        // A manual transport can arrive while either native volume write is
        // awaiting completion. Re-check ownership before runtime monitoring,
        // which may call play() to recover the incoming engine.
        if (transitionWasPreempted()) {
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'fade_volume_write',
            'preempted': _userTransportEpoch != transportEpoch,
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }

        // Runtime DJ monitor: the transition must adapt to the actual A/B
        // engines, not merely the planned timeline. A transient start delay is
        // recovered; a persistent stall falls back to ordinary playback.
        monitorTick++;
        if (monitorTick % 5 == 0) {
          try {
            if (!incoming.playing && linear < 0.92) {
              incomingRecoveryAttempts++;
              await ResonateDiagnostics.record('dj_runtime_monitor', {
                'event': 'incoming_not_playing',
                'attempt': incomingRecoveryAttempts,
                'linear': linear,
                'positionMs': incoming.position.inMilliseconds,
                'songId': nextSong.id,
              });
              if (transitionWasPreempted()) return false;
              if (incomingRecoveryAttempts <= 2) {
                incoming.play();
              } else {
                throw StateError('DJ incoming engine stalled during transition');
              }
            } else if (incoming.playing) {
              final incomingPos = incoming.position.inMilliseconds;
              // Continuous beat-phase correction: use a tiny temporary speed
              // change instead of seeking. This preserves audio continuity and
              // lets the incoming engine converge toward the detected beat grid.
              final now = DateTime.now();
              if (_djRuntimeCorrectionUntil != null && now.isAfter(_djRuntimeCorrectionUntil!)) {
                try { await incoming.setSpeed(_djRuntimeCorrectionBaseSpeed); } catch (_) {}
                if (transitionWasPreempted()) return false;
                _djRuntimeCorrectionUntil = null;
              }
              if (runtimeBeatMs.length >= 4 &&
                  _djBeatCorrectionAttempts < 2 &&
                  (runtimeBpm ?? 0) >= 40 &&
                  (runtimeBpm ?? 0) <= 240 &&
                  linear > 0.08 &&
                  linear < 0.92) {
                var nearest = runtimeBeatMs.first;
                var distance = (incomingPos - nearest).abs();
                for (final beat in runtimeBeatMs) {
                  final d = (incomingPos - beat).abs();
                  if (d < distance) {
                    distance = d;
                    nearest = beat;
                  }
                  if (beat > incomingPos + 250) break;
                }
                final driftMs = incomingPos - nearest;
                final decision = _djBeatDriftCorrector.decide(
                  driftMs: driftMs,
                  bpm: runtimeBpm!,
                  baseSpeed: _djRuntimeCorrectionBaseSpeed,
                );
                if (decision != null) {
                  _djBeatCorrectionAttempts++;
                  try {
                    await incoming.setSpeed(decision.speed);
                    if (transitionWasPreempted()) return false;
                    _djRuntimeCorrectionUntil = now.add(Duration(milliseconds: decision.holdMs));
                    await ResonateDiagnostics.record('dj_runtime_monitor', {
                      'event': 'beat_phase_speed_corrected',
                      'attempt': _djBeatCorrectionAttempts,
                      'fromPositionMs': incomingPos,
                      'targetBeatMs': nearest,
                      'driftMs': decision.driftMs,
                      'speed': decision.speed,
                      'baseSpeed': _djRuntimeCorrectionBaseSpeed,
                      'holdMs': decision.holdMs,
                      'linear': linear,
                      'songId': nextSong.id,
                    });
                    if (transitionWasPreempted()) return false;
                  } catch (_) {}
                }
              }
              if (incomingPos > lastIncomingPositionMs + 20) {
                lastIncomingPositionMs = incomingPos;
                lastIncomingProgressAt = DateTime.now();
                incomingRecoveryAttempts = 0;
              } else if (DateTime.now().difference(lastIncomingProgressAt).inMilliseconds > 900 &&
                  linear < 0.92) {
                incomingRecoveryAttempts++;
                await ResonateDiagnostics.record('dj_runtime_monitor', {
                  'event': 'incoming_position_stalled',
                  'attempt': incomingRecoveryAttempts,
                  'linear': linear,
                  'positionMs': incomingPos,
                  'songId': nextSong.id,
                });
                if (transitionWasPreempted()) return false;
                if (incomingRecoveryAttempts <= 2) {
                  incoming.play();
                  lastIncomingProgressAt = DateTime.now();
                } else {
                  throw StateError('DJ incoming position stalled during transition');
                }
              }
            }
          } catch (e) {
            if (e is StateError) rethrow;
            // Monitoring itself must never become a playback failure.
          }
        }

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
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'after_fade_sfx_restore',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      // Guarantee silence on outgoing before pause/stop — never cut from a
      // still-audible level (the "sudden volume loss" symptom).
      for (var s = 0; s < 3; s++) {
        if (transitionWasPreempted()) {
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'outgoing_mute',
            'preempted': _userTransportEpoch != transportEpoch,
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }
        try { await outgoing.setVolume(0.0); } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 25));
        try {
          if (outgoing.volume <= 0.02) break;
        } catch (_) {
          break;
        }
      }
      if (_userTransportEpoch != transportEpoch ||
          _automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) {
        await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'commit', 'preempted': _userTransportEpoch != transportEpoch, 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
      // Finish the outgoing history record while currentSong still refers to it.
      // Mutating currentSong first caused history to be attributed to the next track.
      await _finishHistoryEvent();
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'finish_history',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      // Pause only after volume is already 0 so pause cannot audibly chop the tail.
      try { await outgoing.pause(); } catch (_) {}
      if (transitionWasPreempted()) return false;
      try { await incoming.setLoopMode(LoopMode.off); } catch (_) {}
      if (transitionWasPreempted()) return false;
      try { await incoming.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0)); } catch (_) {}
      if (transitionWasPreempted()) return false;
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      if (transitionWasPreempted()) return false;
      try {
        if (incoming.volume < 0.05) await incoming.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
      } catch (_) {}
      if (transitionWasPreempted()) return false;
      // Hard guarantee: incoming must be audible before we flip active engine.
      try {
        await incoming.setSpeed(1.0);
        if (transitionWasPreempted()) return false;
        await incoming.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
        if (transitionWasPreempted()) return false;
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
      if (transitionWasPreempted()) return false;
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active
      _queueIndex = nextIndex;
      currentSong = nextSong;
      // Apply the incoming track's cached trim after this crossfade releases volume ownership.
      _lastCompletionSongId = null;
      currentDuration = nextSong.duration;
      currentPosition = incoming.position;
      // Never inherit a stale mid-track resume for a freshly crossfaded-in song.
      if (currentPosition.inMilliseconds < 2500) {
        _resumeStore.clearSong(nextSong.id);
        if (_resumeSongId == nextSong.id) {
          _resumeSongId = null;
          _resumePositionMs = 0;
        }
      }
      // Audible guarantee: UI must not show B playing while engine is silent.
      try {
        await incoming.setSpeed(1.0);
        if (transitionWasPreempted()) return false;
        await incoming.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
        if (transitionWasPreempted()) return false;
        if (_userWantsPlaying && !incoming.playing) {
          try {
            incoming.play();
          } catch (_) {}
          for (var i = 0; i < 10 && !incoming.playing && _userWantsPlaying; i++) {
            await Future<void>.delayed(Duration(milliseconds: 35 + i * 20));
            if (transitionWasPreempted()) return false;
            try {
              incoming.play();
            } catch (_) {}
          }
        }
      } catch (_) {}
      if (transitionWasPreempted()) return false;
      isPlaying = _userWantsPlaying && (incoming.playing || incoming.volume >= 0.05);
      if (_userWantsPlaying && !incoming.playing) {
        // Last resort: hard cut to A with the incoming song (no silent scrub).
        try {
          await _playSongInternal(
            nextSong,
            queue: _queue,
            startIndex: nextIndex,
            playbackIntentToken: intentToken,
          );
        } catch (_) {}
        return audioPlayer.playing;
      }
      await _persistQueue();
      if (transitionWasPreempted()) return false;
      _bindActivePlayerStreams();
      await _startHistoryEvent(nextSong);
      if (transitionWasPreempted()) return false;
      _publishServiceState();
      notifyListeners();
      if (transitionWasPreempted()) return false;
      try { await outgoing.stop(); } catch (_) {}
      if (transitionWasPreempted()) return false;
      // Restore volume on the now-idle engine so the next time it is used it is not stuck at 0.
      try { await outgoing.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0)); } catch (_) {}
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
      // Cancellation can race any awaited engine operation. If a user command
      // or newer transition has taken ownership, do not run failure recovery
      // against the shared A/B players (the "incoming" engine may now be the
      // user's selected track).
      if (_userTransportEpoch != transportEpoch ||
          _automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'stale_failure_cleanup',
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'error': e.toString(),
          'intentToken': intentToken,
        });
        return false;
      }
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      debugPrint('True crossfade failed: $e'); debugPrint('$stack');
      try { await incoming.stop(); } catch (_) {}
      try { await outgoing.setSpeed(1.0); } catch (_) {}
      try { await incoming.setSpeed(1.0); } catch (_) {}
      try { await outgoing.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0)); } catch (_) {}
      try {
        if (outgoing.playing && outgoing.volume < 0.02) {
          await outgoing.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
        }
      } catch (_) {}
      await ResonateDiagnostics.record('crossfade_failed', {'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'error': e.toString(), 'intentToken': intentToken});
      // Hard execution failures are stronger negative learning than a later
      // manual skip. User cancellation/preemption exits before this catch.
      if (_djHandoffsLive &&
          outgoingSong != null &&
          _lastDjStrategy != null) {
        unawaited(DjTransitionMemory.recordOutcome(
          fromId: outgoingSong.id,
          toId: nextSong.id,
          strategy: _lastDjStrategy!,
          successful: false,
          weight: (_lastDjRecoveryAttempts + 1).clamp(1, 3),
          score: _lastDjTransitionScore,
          confidence: _lastDjTransitionConfidence,
          risks: _lastDjTransitionRisks,
          transitionDurationMs: _lastDjTransitionDurationMs,
          recoveryAttempts: _lastDjRecoveryAttempts,
        ));
        unawaited(ResonateDiagnostics.recordDj(
          stage: 'learn',
          outcome: 'execution_failure',
          reason: _lastDjStrategy!,
          songId: nextSong.id,
          extra: {
            'fromId': outgoingSong.id,
            'error': e.toString(),
            'recoveryAttempts': _lastDjRecoveryAttempts,
          },
        ));
      }
      try {
        await ResonateDiagnostics.recordDj(
          stage: 'crossfade',
          outcome: 'failed',
          reason: e.toString(),
          songId: nextSong.id,
        );
      } catch (_) {}
      if (_automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) return false;
      try { await outgoing.stop(); await _playSongInternal(nextSong, queue: _queue, startIndex: nextIndex, playbackIntentToken: intentToken); return true; } catch (fallbackError) { debugPrint('Crossfade fallback failed: $fallbackError'); await ResonateDiagnostics.record('crossfade_fallback_failed', {'incomingSongId': nextSong.id, 'error': fallbackError.toString(), 'intentToken': intentToken}); return false; }
    } finally {
      // A stale transition may finish after a newer user/automatic command.
      // Its cleanup must never touch resources currently owned by the newer
      // transition. This matters because A/B reuses the same two engine/effect
      // instances across rapid Next/Previous commands.
      final ownsTransition = _automaticTransitionGeneration == transitionGeneration;
      if (ownsTransition) {
        _crossfadeInProgress = false;
        _automaticCrossfadeInFlight = false;
        _transitionArmedAt = null;
        unawaited(_refreshTrackLevelingFor(currentSong));
        try {
          await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
        } catch (_) {}
        try {
          await _restoreDjTransitionSfx();
        } catch (_) {}
        _lastDjBassDuckNeeded = false;
        _lastDjIncomingBeatMs = const <int>[];
        _lastDjIncomingBpm = null;
        _djBeatCorrectionAttempts = 0;
        _djRuntimeCorrectionBaseSpeed = 1.0;
        _djRuntimeCorrectionUntil = null;
      } else if (!_crossfadeInProgress && bassDuckOriginal.isNotEmpty) {
        // No newer transition took ownership, so the cancelled transition
        // still needs to restore its own captured EQ state.
        try {
          await _audioEffectsController.restoreBassAfterTransition(
            equalizer: incomingEq,
            original: bassDuckOriginal,
          );
          await ResonateDiagnostics.record('dj_bass_duck', {
            'action': 'restore_stale',
            'bands': bassDuckOriginal.keys.toList(),
            'songId': nextSong.id,
          });
        } catch (_) {}
      }
      if (ownsTransition && bassDuckOriginal.isNotEmpty) {
        try {
          await _audioEffectsController.restoreBassAfterTransition(
            equalizer: incomingEq,
            original: bassDuckOriginal,
          );
          await ResonateDiagnostics.record('dj_bass_duck', {
            'action': 'restore',
            'bands': bassDuckOriginal.keys.toList(),
            'songId': nextSong.id,
          });
        } catch (_) {}
      }
      // A stale transition must never "unstick" the current active engine:
      // it may now belong to a manual track selection with intentional gain.
      if (ownsTransition) {
        try {
          final active = audioPlayer;
          final vol = _effectiveCrossfadeMaster.clamp(0.05, 1.0).toDouble();
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
        // Capture the final state of both reusable engines after transition
        // cleanup. A volume value alone is insufficient: a player can report
        // volume 1.0 while stopped, or retain a DJ stretch speed after handoff.
        try {
          final active = audioPlayer;
          final inactive = inactivePlayer;
          await ResonateDiagnostics.record('crossfade_final_engine_state', {
            'activeEngine': _activeIsA ? 'A' : 'B',
            'activeSongId': currentSong?.id,
            'activeVolume': active.volume,
            'activeSpeed': active.speed,
            'activePlaying': active.playing,
            'inactiveVolume': inactive.volume,
            'inactiveSpeed': inactive.speed,
            'inactivePlaying': inactive.playing,
            'userWantsPlaying': _userWantsPlaying,
            'crossfadeInProgress': _crossfadeInProgress,
          });
        } catch (_) {}
      }
      if (!_crossfadeInProgress && _unduckPendingAfterCrossfade) {
        // The transition (or a newer transport that cancelled it) no longer owns
        // the engines, so finish the deferred focus-gain restoration safely.
        unawaited(_unduckAfterInterruption());
      }
      notifyListeners();

      // Critical fix: if the outgoing track reached completed while we were
      // crossfading, the normal completion path was suppressed. Force
      // continuation now that the hand-off is finished.
      if (_completionObservedDuringCrossfade) {
        final completedSongId = _completionObservedSongId;
        final completedStillCurrent = completedSongId != null &&
            currentSong?.id == completedSongId;
        _completionObservedDuringCrossfade = false;
        _completionObservedSongId = null;
        if (!_completionAdvanceInProgress) {
          unawaited(ResonateDiagnostics.record('completion_transition_recovered', {
            'result': completedStillCurrent
                ? 'advance_completed_track'
                : 'continue_committed_track',
            'completedSongId': completedSongId,
            'currentSongId': currentSong?.id,
            'queueIndex': _queueIndex,
            'queueLength': _queue.length,
          }));
          if (completedStillCurrent) {
            // The transition did not commit a new queue item. Completion was
            // suppressed while the fade owned the player, so explicitly hand
            // the completed song back to the single completion path.
            unawaited(onTrackEnded(completedSongId!));
          } else {
            unawaited(_ensureContinueAfterCrossfade());
          }
        }
      } else {
        _completionObservedSongId = null;
        _completionObservedDuringCrossfade = false;
      }
    }
  }


  /// Phase 4: user transport always wins over automatic work.
  void _cancelAutomaticPlaybackWork() {
    // Invalidate all in-flight automatic A/B work before starting the user's
    // transport operation. Old futures may still unwind, but cannot commit.
    final hadRepeatSelfHandoff = _repeatSelfHandoffArmed || _repeatSelfHandoffInFlight;
    _repeatSelfGeneration++;
    _userTransportEpoch++;
    final cancellationEpoch = _userTransportEpoch;
    _automaticTransitionGeneration++;
    final cancellationGeneration = _automaticTransitionGeneration;
    bool stillOwnsCancellation() =>
        _userTransportEpoch == cancellationEpoch &&
        _automaticTransitionGeneration == cancellationGeneration;
    // A resume/duck/route-recovery fade must not keep writing volume after
    // a newer manual transport command takes ownership.
    _volumeFadeGen++;
    _clearTransitionFlags(clearRepeatSelf: false);
    if (hadRepeatSelfHandoff) {
      unawaited(ResonateDiagnostics.record('repeat_self_cancel', {
        'reason': 'transport_cancel',
        'songId': _repeatSelfTargetSongId,
      }));
    }
    _repeatSelfHandoffArmed = false;
    _repeatSelfHandoffInFlight = false;
    _repeatSelfTargetSongId = null;
    unawaited(_restoreDjTransitionSfx());
    unawaited(() async {
      try {
        final idle = inactivePlayer;
        final active = audioPlayer;
        try {
          await idle.pause();
        } catch (_) {}
        // The idle engine can become active while pause() is awaiting. Never
        // let this stale cleanup mute an engine claimed by a newer transition.
        if (!stillOwnsCancellation()) return;
        try {
          await idle.setVolume(0.0);
        } catch (_) {}
        if (!stillOwnsCancellation()) return;
        try {
          await _clearDjStretchSpeeds(outgoing: active, incoming: idle);
        } catch (_) {}
        if (!stillOwnsCancellation()) return;
        // Always re-clamp active master after cancel (sleep fade + duck aware).
        if (stillOwnsCancellation() && identical(active, audioPlayer)) {
          try {
            await active.setVolume(_effectiveCrossfadeMaster.clamp(0.0, 1.0));
          } catch (_) {}
        }
      } catch (_) {}
    }());
  }

  bool get _recentlyUserPaused {
    final at = _lastUserPauseAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(seconds: 2);
  }

  void _forceClearStuckTransition({String reason = 'watchdog'}) {
    if (!_crossfadeInProgress && !_automaticCrossfadeInFlight) {
      _transitionArmedAt = null;
      return;
    }
    final armed = _transitionArmedAt;
    if (armed != null &&
        DateTime.now().difference(armed) < const Duration(seconds: 22)) {
      return;
    }
    // Clearing flags alone does not cancel the old Future. If it is suspended
    // in a native player call (for example while the screen is off), it could
    // resume later and commit a second engine handoff. Invalidate ownership
    // before releasing the flags so all stale continuations fail their guards.
    final invalidatedGeneration = _automaticTransitionGeneration;
    _automaticTransitionGeneration++;
    _preloadedNextSongId = null;
    _crossfadePreloadInFlight = false;
    unawaited(ResonateDiagnostics.record('stuck_transition_cleared', {
      'reason': reason,
      'crossfadeInProgress': _crossfadeInProgress,
      'automaticCrossfadeInFlight': _automaticCrossfadeInFlight,
      'armedMs': armed == null
          ? null
          : DateTime.now().difference(armed).inMilliseconds,
      'songId': currentSong?.id,
      'invalidatedGeneration': invalidatedGeneration,
      'currentGeneration': _automaticTransitionGeneration,
    }));
    _crossfadeInProgress = false;
    _automaticCrossfadeInFlight = false;
    _repeatSelfHandoffInFlight = false;
    _transitionArmedAt = null;
    unawaited(_restoreDjTransitionSfx());
    unawaited(() async {
      try {
        await inactivePlayer.pause();
      } catch (_) {}
      try {
        await inactivePlayer.setVolume(0.0);
      } catch (_) {}
      try {
        await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
      } catch (_) {}
    }());
  }

  /// Explicit play/resume — used by media-session onPlay and as the play half of toggle.
  /// Never toggles; never pauses.
  Future<void> resumePlayback({String source = 'normal_player'}) {
    _podcastSession.onResumed(currentPosition);
    _audiobookSession.onResumed(currentPosition);
    _modes?.onPlaybackResumed(currentSong);
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      try {
        _userWantsPlaying = true;
        _isDucked = false;
        if (audioPlayer.audioSource != null) {
          try {
            if (source != 'system') {
              final session = await AudioSession.instance;
              await session.setActive(true);
            }
          } catch (_) {}
          // If we are sitting on a completed source, seek to zero first.
          if (audioPlayer.processingState == ProcessingState.completed) {
            try {
              await audioPlayer.seek(Duration.zero);
            } catch (_) {}
          }
          final midTransition = _transitionLive;
          final target = _effectiveCrossfadeMaster.clamp(0.0, 1.0);
          // Start quiet then fade in (skip only during a real ramp).
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
    // Prefer optimistic isPlaying when native lags; user pause must win.
    final wantPause = isPlaying || audioPlayer.playing || _userWantsPlaying;
    if (wantPause) {
      return pause(source: source);
    }
    return resumePlayback(source: source);
  }


  Future<void> pause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    final fromSystemFocus = source == 'system';
    final fromNoisy = source == 'becoming_noisy';
    // Clear user intent immediately (before async lane) so stream listeners and
    // ensureAudiblePlayback cannot race a late play() back in.
    if (!fromSystemFocus) {
      _userWantsPlaying = false;
      isPlaying = false;
      _lastUserPauseAt = DateTime.now();
      _volumeFadeGen++;
      _cancelAutomaticPlaybackWork();
      _crossfadeInProgress = false;
      _automaticCrossfadeInFlight = false;
      _repeatSelfHandoffInFlight = false;
      notifyListeners();
      _publishServiceState();
    }
    return _serializePlayback(() async {
      try {
        if (!fromSystemFocus) {
          _userWantsPlaying = false;
        }
        final midTransition =
            _crossfadeInProgress || _repeatSelfHandoffInFlight;
        try {
          await audioPlayer.pause();
        } catch (_) {}
        try {
          await inactivePlayer.pause();
        } catch (_) {}
        try {
          await _playerA.pause();
        } catch (_) {}
        try {
          await _playerB.pause();
        } catch (_) {}
        if (!midTransition) {
          try {
            await audioPlayer.setVolume(_effectiveCrossfadeMaster.clamp(0.0, 1.0));
          } catch (_) {}
          try {
            await inactivePlayer.setVolume(0.0);
          } catch (_) {}
        }
        isPlaying = false;
        _isDucked = false;
        _persistResumePosition(force: true);
        _podcastSession.onPaused(currentPosition);
    _audiobookSession.onPaused(currentPosition);
        _modes?.onPlaybackPaused();
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('audio_focus_pause', {
          'source': source,
          'userWantsPlaying': _userWantsPlaying,
          'preservedIntent': fromSystemFocus,
          'hardStop': true,
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
      _podcastSession.onStopped(currentPosition);
    _audiobookSession.onStopped(currentPosition);
      _modes?.onPlaybackStopped();
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
    if (!_gaplessWindow.active || effectiveCrossfadeEnabled) return false;
    if (queueIndex < 0 || queueIndex >= _queue.length) return false;
    final song = _queue[queueIndex];
    final local = _gaplessWindow.songIds.indexOf(song.id);
    if (local < 0) return false;
    try {
      await audioPlayer.seek(Duration.zero, index: local);
      _queueIndex = queueIndex;
      currentSong = song;
      unawaited(_refreshTrackLevelingFor(currentSong));
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
    // Manual Next supersedes an automatic DJ/crossfade transition. The intent
    // token below invalidates the in-flight fade so it cannot commit afterward.
    // Keep queueing only for unrelated transport/load contention.
    if (_transportInFlight || _loadingSource) {
      _pendingNextSteps = (_pendingNextSteps + 1).clamp(0, 12);
      return Future<void>.value();
    }
    final wasCrossfadeActive = _crossfadeInProgress || _automaticCrossfadeInFlight;
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    if (wasCrossfadeActive) {
      unawaited(ResonateDiagnostics.record('automatic_transition_preempted', {
        'command': 'next',
        'source': source,
        'songId': currentSong?.id,
        'queueIndex': _queueIndex,
      }));
    }

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
                score: _lastDjTransitionScore,
                confidence: _lastDjTransitionConfidence,
                risks: _lastDjTransitionRisks,
                transitionDurationMs: _lastDjTransitionDurationMs,
                recoveryAttempts: _lastDjRecoveryAttempts,
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
          unawaited(_refreshTrackLevelingFor(currentSong));
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
            if (_historySession.activeEvent != null) _historySession.positionMs = 0;
            _persistResumePosition(force: true);
            notifyListeners();
            _publishServiceState();
          }
        } finally {
          _transportInFlight = false;
          unawaited(_refreshTrackLevelingFor(currentSong));
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
          if (_historySession.activeEvent != null) {
            _historySession.positionMs = safe.inMilliseconds;
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
      // Keep EQ preamp + sleep-fade digital attenuation; system volume is separate.
      if (!_transitionLive) {
        await _applyActiveMasterVolume();
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Called by EqualizerProvider for preamp (−6 dB → ~0.5 scale, 0 dB → 1.0).
  Future<void> setEqPreampScale(double scale) async {
    _eqPreampUserScale = scale.clamp(0.25, 1.0).toDouble();
    _eqPreampScale = (_eqPreampUserScale * _trackLevelingScale).clamp(0.0, 1.0).toDouble();
    if (_transitionLive) {
      notifyListeners();
      return;
    }
    await _applyActiveMasterVolume();
    notifyListeners();
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async { if (songs.isEmpty) { await _finishHistoryEvent(); _queue = <Song>[]; _queueIndex = 0; await _persistQueue(); notifyListeners(); return; } final index = startIndex.clamp(0, songs.length - 1).toInt(); await playSong(songs[index], queue: songs, startIndex: index); }
  Stream<Duration?> get durationStream => audioPlayer.durationStream;
  @override
  void dispose() {
    _systemVolumePollTimer?.cancel();
    _endOfTrackWatchdog?.cancel();
    _modes?.removeListener(_onModesChangedForSessions);
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _volumeSubscription?.cancel();
    _interruptionSubscription?.cancel();
    _noisySubscription?.cancel();
    _sessionASub?.cancel();
    _sessionBSub?.cancel();
    unawaited(_engines.dispose());
    super.dispose();
  }
}
