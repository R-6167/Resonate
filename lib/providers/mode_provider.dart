import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_type.dart';
import '../models/playback_policy.dart';
import '../models/resonate_mode.dart';
import '../models/song.dart';
import 'music_provider.dart';
import '../services/media_classification_store.dart';
import '../services/media_classifier.dart';
import '../services/mode_policy_catalog.dart';

/// Mode Engine entry point.
/// Sits above playback: exposes [policy] for engines and UI to consume.
class ModeProvider extends ChangeNotifier {
  static const _modeKey = 'resonate_active_mode_v1';

  final MediaClassifier _classifier = MediaClassifier.instance;
  final MediaClassificationStore _store = MediaClassificationStore();
  MusicProvider? _music;

  ResonateMode _mode = ResonateMode.normal;
  Map<String, MediaClassification> _userOverrides = {};
  bool _ready = false;

  ResonateMode get mode => _mode;
  PlaybackPolicy get policy => ModePolicyCatalog.policyFor(_mode);
  bool get isReady => _ready;

  ModeProvider() {
    _init();
  }

  /// Bind the single playback engine so policy can gate crossfade/shuffle.
  void attachMusic(MusicProvider music) {
    _music = music;
    _pushPolicyToEngine();
  }

  void _pushPolicyToEngine() {
    final p = policy;
    _music?.applyModePlaybackPolicy(
      crossfadeAllowed: p.crossfadeAllowed,
      shuffleAllowed: p.shuffleAllowed,
    );
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = ResonateModeX.fromId(prefs.getString(_modeKey));
      _userOverrides = await _store.loadAll();
    } catch (e) {
      debugPrint('ModeProvider init: $e');
    }
    _ready = true;
    _pushPolicyToEngine();
    notifyListeners();
  }

  Future<void> setMode(ResonateMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    _pushPolicyToEngine();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, mode.id);
    } catch (e) {
      debugPrint('ModeProvider save mode: $e');
    }
  }

  /// Effective classification: user override wins over automatic.
  MediaClassification classificationFor(Song song) {
    final user = _userOverrides[song.id];
    if (user != null) return user;
    return _classifier.classify(song);
  }

  MediaType mediaTypeFor(Song song) => classificationFor(song).type;

  Future<void> setUserMediaType(Song song, MediaType type) async {
    await _store.setOverride(song.id, type);
    _userOverrides[song.id] = MediaClassification(
      type: type,
      confidence: 1.0,
      source: ClassificationSource.user,
      reason: 'User override',
    );
    notifyListeners();
  }

  Future<void> clearUserMediaType(Song song) async {
    await _store.clearOverride(song.id);
    _userOverrides.remove(song.id);
    notifyListeners();
  }

  /// Soft content filter for AutoNext / Intelligence (never blocks explicit play).
  /// Rejects avoided types; requires preferred match when the mode has a prefer set.
  bool shouldPreferSong(Song song) {
    final type = mediaTypeFor(song);
    final p = policy;
    if (!p.allowsMediaType(type)) return false;
    return p.prefersMediaType(type);
  }

  /// Autopilot may pick this track (not on the avoided list).
  /// Explicit user play is never blocked by this.
  bool isAcceptableForAutopilot(Song song) {
    return policy.allowsMediaType(mediaTypeFor(song));
  }

  /// Mode actively prefers this content kind (empty prefer set = no bias).
  bool isPreferredContent(Song song) {
    return policy.prefersMediaType(mediaTypeFor(song));
  }

  /// Sort key: preferred first, then acceptable, avoided last (-1).
  int contentBiasScore(Song song) {
    final type = mediaTypeFor(song);
    final p = policy;
    if (!p.allowsMediaType(type)) return -1;
    if (p.preferredMediaTypes.isEmpty) return 1;
    if (p.preferredMediaTypes.contains(type)) return 2;
    return 0; // allowed but not preferred (e.g. unknown while Running)
  }

  /// Whether crossfade is allowed under the active mode policy.
  bool get crossfadeAllowed => policy.crossfadeAllowed;
}
