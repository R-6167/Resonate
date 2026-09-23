import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/dj_analysis_service.dart';
import '../services/dj_mode_settings_store.dart';
import 'music_provider.dart';

/// Optional DJ Mode layer — same obedience model as Intelligence.
///
/// When [isEnabled] is false (default), every feature gate is off and
/// [MusicProvider] playback / crossfade behavior is unchanged.
class DjModeProvider extends ChangeNotifier {
  DjModeProvider({required this.music, DjAnalysisService? analysis})
      : _analysis = analysis ?? DjAnalysisService() {
    unawaited(_load());
  }

  final MusicProvider music;
  final DjAnalysisService _analysis;

  bool _enabled = false;
  bool _beatAlign = true;
  bool _tempoMatch = false;
  bool _harmonicMix = false;
  int _maxStretchPercent = 12;
  bool _analyzeIdle = false;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get isEnabled => _enabled;

  /// Effective gates: always false when master is off (like Intelligence).
  bool get beatAlignActive => _enabled && _beatAlign;
  bool get tempoMatchActive => _enabled && _tempoMatch;
  bool get harmonicMixActive => _enabled && _harmonicMix;
  bool get analyzeIdleActive => _enabled && _analyzeIdle;

  bool get beatAlign => _beatAlign;
  bool get tempoMatch => _tempoMatch;
  bool get harmonicMix => _harmonicMix;
  int get maxStretchPercent => _maxStretchPercent;
  bool get analyzeIdle => _analyzeIdle;

  DjAnalysisService get analysis => _analysis;

  Future<void> _load() async {
    try {
      _enabled = await DjModeSettingsStore.enabled();
      _beatAlign = await DjModeSettingsStore.beatAlign();
      _tempoMatch = await DjModeSettingsStore.tempoMatch();
      _harmonicMix = await DjModeSettingsStore.harmonicMix();
      _maxStretchPercent = await DjModeSettingsStore.maxStretchPercent();
      _analyzeIdle = await DjModeSettingsStore.analyzeIdle();
    } catch (e) {
      debugPrint('DjModeProvider load failed: $e');
    }
    _loaded = true;
    _syncToMusic();
    notifyListeners();
  }

  void _syncToMusic() {
    try {
      music.configureDjMode(
        beatAlignActive: beatAlignActive,
        analysis: _analysis,
      );
    } catch (e) {
      debugPrint('DjMode sync to music failed: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    _syncToMusic();
    notifyListeners();
    try {
      await DjModeSettingsStore.setEnabled(value);
    } catch (e) {
      debugPrint('DjMode setEnabled failed: $e');
    }
  }

  Future<void> setBeatAlign(bool value) async {
    _beatAlign = value;
    _syncToMusic();
    notifyListeners();
    await DjModeSettingsStore.setBeatAlign(value);
  }

  Future<void> setTempoMatch(bool value) async {
    _tempoMatch = value;
    notifyListeners();
    await DjModeSettingsStore.setTempoMatch(value);
  }

  Future<void> setHarmonicMix(bool value) async {
    _harmonicMix = value;
    notifyListeners();
    await DjModeSettingsStore.setHarmonicMix(value);
  }

  Future<void> setMaxStretchPercent(int value) async {
    _maxStretchPercent = value.clamp(3, 20);
    notifyListeners();
    await DjModeSettingsStore.setMaxStretchPercent(_maxStretchPercent);
  }

  Future<void> setAnalyzeIdle(bool value) async {
    _analyzeIdle = value;
    notifyListeners();
    await DjModeSettingsStore.setAnalyzeIdle(value);
  }
}
