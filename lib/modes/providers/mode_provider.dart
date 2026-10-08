import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/song.dart';
import '../models/media_type.dart';
import '../models/mode_media_item.dart';
import '../models/playback_policy.dart';
import '../models/resonate_mode.dart';
import '../models/running_intent.dart';
import '../models/running_session_state.dart';
import '../services/media_classification_store.dart';
import '../services/media_classifier.dart';
import '../services/media_folder_router.dart';
import '../services/media_folder_store.dart';
import '../services/mode_policy_catalog.dart';
import '../services/mode_interaction_catalog.dart';
import '../services/driving_coordinator.dart';
import '../services/motivation_coordinator.dart';
import '../services/work_coordinator.dart';
import '../services/running_coordinator.dart';
import '../models/interaction_policy.dart';
import '../models/motivation_intent.dart';
import '../models/work_intent.dart';
import '../models/driving_intent.dart';
import '../integration/mode_context_port.dart';
import '../integration/mode_playback_port.dart';
import '../integration/mode_motion_port.dart';

/// Central Modes Engine. It emits policy and delegates playback/context work
/// to adapters supplied by the main Resonate application.
class ModeProvider extends ChangeNotifier {
  static const _modeKey = 'resonate_modes_active_mode_v1';
  static const _autoEnterDrivingKey = 'resonate_modes_auto_enter_driving_v1';

  final MediaClassifier _classifier = MediaClassifier.instance;
  final MediaClassificationStore _store = MediaClassificationStore();
  final MediaFolderStore _folderStore = MediaFolderStore();
  final DrivingCoordinator _drivingCoordinator = DrivingCoordinator();
  final RunningCoordinator _runningCoordinator = RunningCoordinator();
  List<DrivingIntent> _lastDrivingIntents = const <DrivingIntent>[];
  List<RunningIntent> _lastRunningIntents = const <RunningIntent>[];

  ModeMotionPort? _motion;
  bool Function()? _isPlaying;
  void Function(RunningIntent intent)? _runningIntentSink;

  ModePlaybackPort? _playback;
  ModeContextPort? _context;
  ResonateMode _mode = ResonateMode.normal;
  Map<String, MediaClassification> _userOverrides = {};
  Map<MediaType, List<String>> _mediaFolders = {};
  bool _ready = false;
  bool _drivingSuggestOpen = false;
  bool _drivingSuggestDismissed = false;
  bool _autoEnterDrivingOnCar = false;
  late final Future<void> _readyFuture = _init();

  ModeProvider();

  Future<void> get ready => _readyFuture;
  ResonateMode get mode => _mode;
  PlaybackPolicy get policy => ModePolicyCatalog.policyFor(_mode);
  InteractionPolicy get interactionPolicy => ModeInteractionCatalog.policyFor(_mode);
  bool get isReady => _ready;
  bool get hasDrivingSuggestion =>
      _drivingSuggestOpen && _mode != ResonateMode.driving && !_autoEnterDrivingOnCar;
  bool get autoEnterDrivingOnCar => _autoEnterDrivingOnCar;
  bool get drivingContextActive => _drivingCoordinator.context == ModeAudioContext.car;
  List<DrivingIntent> get lastDrivingIntents => List.unmodifiable(_lastDrivingIntents);
  List<RunningIntent> get lastRunningIntents => List.unmodifiable(_lastRunningIntents);
  RunningSessionState get runningSessionState => _runningCoordinator.state;
  bool get runningSessionActive => _runningCoordinator.state == RunningSessionState.active;
  bool get crossfadeAllowed => policy.crossfadeAllowed;
  final MotivationCoordinator _motivationCoordinator = MotivationCoordinator();
  final WorkCoordinator _workCoordinator = WorkCoordinator();
  List<MotivationIntent> _lastMotivationIntents = const <MotivationIntent>[];
  List<WorkIntent> _lastWorkIntents = const <WorkIntent>[];

  List<MotivationIntent> get lastMotivationIntents => List.unmodifiable(_lastMotivationIntents);
  List<WorkIntent> get lastWorkIntents => List.unmodifiable(_lastWorkIntents);
  bool get motivationSessionActive => _motivationCoordinator.isActive;
  bool get workSessionActive => _workCoordinator.isActive;

  List<String> foldersFor(MediaType type) =>
      List.unmodifiable(_mediaFolders[type] ?? const <String>[]);

  bool hasFolderFor(MediaType type, String path) =>
      MediaFolderRouter(_mediaFolders).hasFolder(type, path);

  Future<void> addMediaFolder(MediaType type, String path) async {
    if (!MediaFolderStore.supportedTypes.contains(type)) return;
    await _folderStore.addFolder(type, path);
    _mediaFolders = await _folderStore.loadAll();
    notifyListeners();
  }

  Future<void> removeMediaFolder(MediaType type, String path) async {
    if (!MediaFolderStore.supportedTypes.contains(type)) return;
    await _folderStore.removeFolder(type, path);
    _mediaFolders = await _folderStore.loadAll();
    notifyListeners();
  }

  Future<void> clearMediaFolders(MediaType type) async {
    if (!MediaFolderStore.supportedTypes.contains(type)) return;
    await _folderStore.clearFolders(type);
    _mediaFolders = await _folderStore.loadAll();
    notifyListeners();
  }

  void attachPlayback(ModePlaybackPort playback) {
    _playback = playback;
    _pushPolicyToEngine();
  }

  void attachContext(ModeContextPort context) {
    _context?.removeListener(_onContextChanged);
    _context = context;
    context.addListener(_onContextChanged);
    _onContextChanged();
  }

  void attachMotion(
    ModeMotionPort motion, {
    required bool Function() isPlaying,
    void Function(RunningIntent intent)? onIntent,
  }) {
    _motion?.removeListener(_onMotionChanged);
    _motion?.stop();
    _motion = motion;
    _isPlaying = isPlaying;
    _runningIntentSink = onIntent;
    motion.addListener(_onMotionChanged);
    if (_mode == ResonateMode.running) {
      motion.start();
    }
  }

  void _onMotionChanged() {
    if (_mode != ResonateMode.running) return;
    final state = _motion?.motionState;
    final isPlaying = _isPlaying;
    if (state == null || isPlaying == null) return;
    _publishRunningIntents(
      _runningCoordinator.ingestMotion(
        state,
        DateTime.now(),
        isPlaying: isPlaying(),
      ),
    );
  }

  void _publishRunningIntents(List<RunningIntent> intents) {
    if (intents.isEmpty) return;
    _lastRunningIntents = List<RunningIntent>.unmodifiable(intents);
    for (final intent in intents) {
      try {
        _runningIntentSink?.call(intent);
      } catch (_) {}
    }
    notifyListeners();
  }

  void setRunningUserPaused(bool paused) {
    if (_mode != ResonateMode.running) return;
    _runningCoordinator.setUserPaused(paused);
  }

  void _enterRunning(DateTime now) {
    if (_runningCoordinator.state == RunningSessionState.active) return;
    _motion?.start();
    _publishRunningIntents([_runningCoordinator.start(now)]);
  }

  void _exitRunning(DateTime now) {
    if (_runningCoordinator.state == RunningSessionState.idle) {
      _motion?.stop();
      return;
    }
    _publishRunningIntents([_runningCoordinator.exit(now)]);
    _motion?.stop();
  }

  void _publishMotivationIntents(List<MotivationIntent> intents) {
    if (intents.isEmpty) return;
    _lastMotivationIntents = List<MotivationIntent>.unmodifiable(intents);
    notifyListeners();
  }

  void _publishWorkIntents(List<WorkIntent> intents) {
    if (intents.isEmpty) return;
    _lastWorkIntents = List<WorkIntent>.unmodifiable(intents);
    notifyListeners();
  }

  void onPlaybackStarted(Song? song, {Duration position = Duration.zero}) {
    final now = DateTime.now();
    if (_mode == ResonateMode.motivation) {
      final intents = <MotivationIntent>[];
      if (!_motivationCoordinator.isActive) {
        intents.addAll(_motivationCoordinator.start(now));
      }
      if (song != null) {
        final item = ModeMediaItem(id: song.id, filePath: song.filePath, title: song.title, album: song.album, artist: song.artist);
        intents.addAll(_motivationCoordinator.startContent(mediaTypeFor(item), now));
      }
      _publishMotivationIntents(intents);
    } else if (_mode == ResonateMode.work && !_workCoordinator.isActive) {
      _publishWorkIntents(_workCoordinator.start(now));
    }
  }

  void onPlaybackPaused() {
    final now = DateTime.now();
    if (_mode == ResonateMode.motivation) {
      _publishMotivationIntents(_motivationCoordinator.pause(now));
    } else if (_mode == ResonateMode.work) {
      _publishWorkIntents(_workCoordinator.pause(now));
    }
  }

  void onPlaybackResumed(Song? song) {
    final now = DateTime.now();
    if (_mode == ResonateMode.motivation) {
      if (!_motivationCoordinator.isActive) {
        onPlaybackStarted(song);
      } else {
        _publishMotivationIntents(_motivationCoordinator.resume(now));
      }
    } else if (_mode == ResonateMode.work) {
      if (!_workCoordinator.isActive) {
        _publishWorkIntents(_workCoordinator.start(now));
      } else {
        _publishWorkIntents(_workCoordinator.resume(now));
      }
    }
  }

  void onPlaybackCompleted(Song? song) {
    if (_mode != ResonateMode.motivation || song == null) return;
    final item = ModeMediaItem(id: song.id, filePath: song.filePath, title: song.title, album: song.album, artist: song.artist);
    _publishMotivationIntents(
      _motivationCoordinator.completeContent(mediaTypeFor(item), DateTime.now()),
    );
  }

  void onPlaybackStopped() {
    final now = DateTime.now();
    if (_mode == ResonateMode.motivation) {
      _publishMotivationIntents(_motivationCoordinator.complete(now));
    } else if (_mode == ResonateMode.work) {
      _publishWorkIntents(_workCoordinator.complete(now));
    }
  }

  void _onContextChanged() {
    final context = _context?.audioContext ?? ModeAudioContext.unknown;
    _drivingCoordinator.setMode(_mode);
    _lastDrivingIntents = _drivingCoordinator.ingestContext(
      context,
      DateTime.now(),
      autoEnterEnabled: _autoEnterDrivingOnCar,
    );
    final car = context == ModeAudioContext.car;
    if (!car) {
      final changed = _drivingSuggestOpen || _drivingSuggestDismissed;
      _drivingSuggestOpen = false;
      _drivingSuggestDismissed = false;
      if (changed) notifyListeners();
      return;
    }
    if (_mode == ResonateMode.driving) {
      if (_drivingSuggestOpen) {
        _drivingSuggestOpen = false;
        notifyListeners();
      }
      return;
    }
    if (_autoEnterDrivingOnCar) {
      _drivingSuggestOpen = false;
      _drivingSuggestDismissed = false;
      unawaited(setMode(ResonateMode.driving));
      return;
    }
    if (!_drivingSuggestDismissed && !_drivingSuggestOpen) {
      _drivingSuggestOpen = true;
      notifyListeners();
    }
  }

  Future<void> acceptDrivingSuggestion() async {
    _drivingSuggestOpen = false;
    _drivingSuggestDismissed = false;
    await setMode(ResonateMode.driving);
  }

  void dismissDrivingSuggestion() {
    _drivingSuggestOpen = false;
    _drivingSuggestDismissed = true;
    notifyListeners();
  }

  Future<void> setAutoEnterDrivingOnCar(bool value) async {
    if (_autoEnterDrivingOnCar == value) return;
    _autoEnterDrivingOnCar = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoEnterDrivingKey, value);
    } catch (_) {}
    _onContextChanged();
  }

  void _pushPolicyToEngine() {
    final p = policy;
    _playback?.applyModePlaybackPolicy(
      crossfadeAllowed: p.crossfadeAllowed,
      shuffleAllowed: p.shuffleAllowed,
      preciseResume: p.preciseResume,
    );
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = ResonateModeX.fromId(prefs.getString(_modeKey));
      _autoEnterDrivingOnCar = prefs.getBool(_autoEnterDrivingKey) ?? false;
      _userOverrides = await _store.loadAll();
      _mediaFolders = await _folderStore.loadAll();
    } catch (_) {}
    _ready = true;
    _motivationCoordinator.setMode(_mode);
    _workCoordinator.setMode(_mode);
    _pushPolicyToEngine();
    if (_mode == ResonateMode.running) _enterRunning(DateTime.now());
    if (_mode == ResonateMode.motivation) _publishMotivationIntents(_motivationCoordinator.start(DateTime.now()));
    if (_mode == ResonateMode.work) _publishWorkIntents(_workCoordinator.start(DateTime.now()));
    notifyListeners();
  }

  Future<void> setMode(ResonateMode mode) async {
    if (_mode == mode) return;
    final previous = _mode;
    if (previous == ResonateMode.running) _exitRunning(DateTime.now());
    if (previous == ResonateMode.motivation) _publishMotivationIntents(_motivationCoordinator.exit(DateTime.now()));
    if (previous == ResonateMode.work) _publishWorkIntents(_workCoordinator.exit(DateTime.now()));
    _mode = mode;
    _drivingCoordinator.setMode(mode);
    if (mode == ResonateMode.driving) {
      _drivingSuggestOpen = false;
      _drivingSuggestDismissed = false;
    }
    _pushPolicyToEngine();
    if (mode == ResonateMode.running) _enterRunning(DateTime.now());
    if (mode == ResonateMode.motivation) _motivationCoordinator.setMode(mode);
    if (mode == ResonateMode.work) _workCoordinator.setMode(mode);
    _onContextChanged();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, mode.id);
    } catch (_) {}
  }

  MediaClassification classificationFor(ModeMediaItem item) {
    final override = _userOverrides[item.id];
    if (override != null) return override;

    final folderType = MediaFolderRouter(_mediaFolders).typeForPath(item.filePath);
    if (folderType != null) {
      return MediaClassification(
        type: folderType,
        confidence: 1.0,
        source: ClassificationSource.user,
        reason: 'User-selected content folder',
      );
    }

    return _classifier.classify(item);
  }

  MediaType mediaTypeFor(ModeMediaItem item) => classificationFor(item).type;

  Future<void> setUserMediaType(ModeMediaItem item, MediaType type) async {
    await _store.setOverride(item.id, type);
    _userOverrides[item.id] = MediaClassification(
      type: type, confidence: 1.0,
      source: ClassificationSource.user, reason: 'User override',
    );
    notifyListeners();
  }

  Future<void> clearUserMediaType(ModeMediaItem item) async {
    await _store.clearOverride(item.id);
    _userOverrides.remove(item.id);
    notifyListeners();
  }

  bool shouldPreferItem(ModeMediaItem item) {
    final type = mediaTypeFor(item);
    if (!policy.allowsMediaType(type)) return false;
    return policy.prefersMediaType(type);
  }

  bool isAcceptableForAutopilot(ModeMediaItem item) =>
      policy.allowsMediaType(mediaTypeFor(item));

  bool isPreferredContent(ModeMediaItem item) =>
      policy.prefersMediaType(mediaTypeFor(item));

  int contentBiasScore(ModeMediaItem item) {
    final type = mediaTypeFor(item);
    if (!policy.allowsMediaType(type)) return -1;
    if (policy.preferredMediaTypes.isEmpty) return 1;
    return policy.preferredMediaTypes.contains(type) ? 2 : 0;
  }

  @override
  void dispose() {
    _context?.removeListener(_onContextChanged);
    _motion?.removeListener(_onMotionChanged);
    _motion?.stop();
    super.dispose();
  }
}
