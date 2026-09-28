import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:dsp_engine/dsp_engine.dart';

/// Soft wrapper around DSP ENGINE (64-bit Direct Volume Control).
///
/// If `libdsp_engine.so` is missing, methods no-op and [isAvailable] is false.
/// Band EQ continues via AndroidEqualizer + Resonate studio model.
///
/// Runs inside Resonate — app id remains `com.aetherion.resonate`.
class DspEngineBridge {
  DspEngineBridge._();
  static final DspEngineBridge instance = DspEngineBridge._();

  DspEngine? _engine;
  bool _tried = false;
  bool _available = false;
  String _version = 'unavailable';
  String? _lastError;

  bool get isAvailable => _available;
  String get version => _version;
  String? get lastError => _lastError;

  static const String engineId = 'DSP-ENGINE/v0.1-dvc64';

  /// Load native library once. Safe to call from UI or providers.
  Future<bool> ensureInitialized() async {
    if (_tried) return _available;
    _tried = true;
    try {
      _engine = DspEngine.create(DspConfig.mobile());
      _version = DspEngine.version;
      _available = true;
      debugPrint('DSP ENGINE ready: $_version ($engineId)');
      return true;
    } catch (e, st) {
      _available = false;
      _engine = null;
      _lastError = e.toString();
      debugPrint('DSP ENGINE not loaded (Android EQ only): $e');
      assert(() {
        debugPrint('$st');
        return true;
      }());
      return false;
    }
  }

  void setVolumeLinear(double linear) {
    final eng = _engine;
    if (eng == null) return;
    try {
      eng.setVolume(linear.clamp(0.0, 4.0));
    } catch (e) {
      debugPrint('DVC setVolume: $e');
    }
  }

  void setVolumeDb(double db) {
    final eng = _engine;
    if (eng == null) return;
    try {
      eng.setVolumeDb(db.clamp(-24.0, 12.0));
    } catch (e) {
      debugPrint('DVC setVolumeDb: $e');
    }
  }

  void setVolumeRampedDb(double db, {double rampMs = 25}) {
    final eng = _engine;
    if (eng == null) return;
    try {
      final clamped = db.clamp(-24.0, 12.0);
      final lin = clamped <= -60 ? 0.0 : math.pow(10.0, clamped / 20.0).toDouble();
      eng.setVolumeRamped(lin, rampMs: rampMs);
    } catch (e) {
      debugPrint('DVC ramp: $e');
    }
  }

  double get volumeLinear {
    final eng = _engine;
    if (eng == null) return 1.0;
    try {
      return eng.volume;
    } catch (_) {
      return 1.0;
    }
  }

  void dispose() {
    try {
      _engine?.dispose();
    } catch (_) {}
    _engine = null;
    _available = false;
  }
}
