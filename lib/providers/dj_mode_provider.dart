import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/dj_analysis_service.dart';
import '../services/dj_idle_analysis_service.dart';
import '../services/dj_mode_settings_store.dart';
import '../services/resonate_diagnostics.dart';
import 'music_provider.dart';

/// Optional DJ Mode layer — same obedience model as Intelligence.
///
/// When [isEnabled] is false (default), every feature gate is off and
/// [MusicProvider] playback / crossfade behavior is unchanged.
class DjModeProvider extends ChangeNotifier {
  DjModeProvider({required this.music, DjAnalysisService? analysis})
      : _analysis = analysis ?? DjAnalysisService() {
    _idle = DjIdleAnalysisService(analysis: _analysis);
    unawaited(_load());
  }

  final MusicProvider music;
  final DjAnalysisService _analysis;
  late final DjIdleAnalysisService _idle;

  bool _enabled = false;
  bool _beatAlign = true;
  bool _tempoMatch = false;
  bool _harmonicMix = false;
  int _maxStretchPercent = 12;
  bool _analyzeIdle = false;
  bool _transitionSfx = true;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get isEnabled => _enabled;

  /// Effective gates: always false when master is off (like Intelligence).
  bool get beatAlignActive => _enabled && _beatAlign;
  bool get tempoMatchActive => _enabled && _tempoMatch;
  bool get harmonicMixActive => _enabled && _harmonicMix;
  bool get transitionSfx => _transitionSfx;
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
      _transitionSfx = await DjModeSettingsStore.transitionSfx();
    } catch (e) {
      debugPrint('DjModeProvider load failed: $e');
    }
    _loaded = true;
    _syncToMusic();
    notifyListeners();
    _maybeStartIdleScan();
  }

  void _syncToMusic() {
    try {
      music.configureDjMode(
        beatAlignActive: beatAlignActive,
        tempoMatchActive: tempoMatchActive,
        maxStretchPercent: _maxStretchPercent,
        sfxActive: _enabled && _transitionSfx,
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
    if (value) {
      _maybeStartIdleScan();
    } else {
      _idle.stop();
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
    _syncToMusic();
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
    _syncToMusic();
    notifyListeners();
    await DjModeSettingsStore.setMaxStretchPercent(_maxStretchPercent);
  }

  Future<void> setTransitionSfx(bool value) async {
    _transitionSfx = value;
    notifyListeners();
    await DjModeSettingsStore.setTransitionSfx(value);
    _syncToMusic();
  }

  Future<void> setAnalyzeIdle(bool value) async {
    _analyzeIdle = value;
    notifyListeners();
    await DjModeSettingsStore.setAnalyzeIdle(value);
    if (value && _enabled) {
      _maybeStartIdleScan();
    } else {
      _idle.stop();
    }
  }

  void _maybeStartIdleScan() {
    if (!_enabled || !_analyzeIdle) return;
    unawaited(_idle.startIfNeeded(maxSongs: 48));
  }

  /// Manual trigger from settings / diagnostics.
  Future<void> runIdleScanNow({int maxSongs = 48}) async {
    if (!_enabled) {
      await ResonateDiagnostics.recordDj(
        stage: 'idle_scan_rejected',
        outcome: 'failed',
        reason: 'dj_mode_off',
      );
      return;
    }
    await _idle.startIfNeeded(maxSongs: maxSongs);
  }
}
