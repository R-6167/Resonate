import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_type.dart';
import '../models/mode_media_item.dart';
import '../models/playback_policy.dart';
import '../models/resonate_mode.dart';
import '../services/media_classification_store.dart';
import '../services/media_classifier.dart';
import '../services/mode_policy_catalog.dart';
import '../integration/mode_context_port.dart';
import '../integration/mode_playback_port.dart';

/// Central Modes Engine. It emits policy and delegates playback/context work
/// to adapters supplied by the main Resonate application.
class ModeProvider extends ChangeNotifier {
  static const _modeKey = 'resonate_modes_active_mode_v1';
  static const _autoEnterDrivingKey = 'resonate_modes_auto_enter_driving_v1';

  final MediaClassifier _classifier = MediaClassifier.instance;
  final MediaClassificationStore _store = MediaClassificationStore();

  ModePlaybackPort? _playback;
  ModeContextPort? _context;
  ResonateMode _mode = ResonateMode.normal;
  Map<String, MediaClassification> _userOverrides = {};
  bool _ready = false;
  bool _drivingSuggestOpen = false;
  bool _drivingSuggestDismissed = false;
  bool _autoEnterDrivingOnCar = false;
  late final Future<void> _readyFuture = _init();

  ModeProvider();

  Future<void> get ready => _readyFuture;
  ResonateMode get mode => _mode;
  PlaybackPolicy get policy => ModePolicyCatalog.policyFor(_mode);
  bool get isReady => _ready;
  bool get hasDrivingSuggestion =>
      _drivingSuggestOpen && _mode != ResonateMode.driving && !_autoEnterDrivingOnCar;
  bool get autoEnterDrivingOnCar => _autoEnterDrivingOnCar;
  bool get crossfadeAllowed => policy.crossfadeAllowed;

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

  void _onContextChanged() {
    final car = _context?.audioContext == ModeAudioContext.car;
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
    } catch (_) {}
    _ready = true;
    _pushPolicyToEngine();
    notifyListeners();
  }

  Future<void> setMode(ResonateMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    if (mode == ResonateMode.driving) {
      _drivingSuggestOpen = false;
      _drivingSuggestDismissed = false;
    }
    _pushPolicyToEngine();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, mode.id);
    } catch (_) {}
  }

  MediaClassification classificationFor(ModeMediaItem item) =>
      _userOverrides[item.id] ?? _classifier.classify(item);

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
    super.dispose();
  }
}
