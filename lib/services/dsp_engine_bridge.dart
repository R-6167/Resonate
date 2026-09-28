import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:dsp_engine/dsp_engine.dart';

/// Soft wrapper around DSP ENGINE (64-bit DVC + multi-band EQ).
///
/// If `libdsp_engine.so` is missing, methods no-op and [isAvailable] is false.
/// Live multi-band still uses AndroidEqualizer / DynamicsProcessing until a
/// custom ExoPlayer AudioProcessor can call [processBuffer] on the audio thread.
///
/// App id stays `com.aetherion.resonate`.
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

  static const String engineId = 'DSP-ENGINE/v0.2-eq31';

  Future<bool> ensureInitialized() async {
    if (_tried) return _available;
    _tried = true;
    try {
      _engine = DspEngine.create(DspConfig.mobile());
      _version = DspEngine.version;
      _available = true;
      try {
        _engine!.start();
      } catch (_) {}
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
      final lin =
          clamped <= -60 ? 0.0 : math.pow(10.0, clamped / 20.0).toDouble();
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

  // ---- Multi-band EQ (native 31-band) ----

  void setEqEnabled(bool enabled) {
    final eng = _engine;
    if (eng == null) return;
    try {
      eng.eqEnabled = enabled;
    } catch (e) {
      debugPrint('native EQ enable: $e');
    }
  }

  bool get eqEnabled {
    final eng = _engine;
    if (eng == null) return false;
    try {
      return eng.eqEnabled;
    } catch (_) {
      return false;
    }
  }

  int get eqBandCount {
    final eng = _engine;
    if (eng == null) return 0;
    try {
      return eng.eqBandCount;
    } catch (_) {
      return 0;
    }
  }

  /// Push studio centers + gains into the native EQ bank.
  void setEqBands({
    List<double>? centersHz,
    required List<double> gainsDb,
    bool enabled = true,
  }) {
    final eng = _engine;
    if (eng == null) return;
    try {
      eng.setEqBands(centersHz: centersHz, gainsDb: gainsDb);
      eng.eqEnabled = enabled;
    } catch (e) {
      debugPrint('native EQ setBands: $e');
    }
  }

  void resetEq() {
    final eng = _engine;
    if (eng == null) return;
    try {
      eng.resetEq();
    } catch (e) {
      debugPrint('native EQ reset: $e');
    }
  }

  /// Run [dsp_process] on interleaved float32 PCM (offline / self-test).
  ///
  /// Not real-time safe from Dart (allocates); a future media3 AudioProcessor
  /// should call the C ABI on the audio thread with pre-allocated buffers.
  bool processBuffer(Float32List input, Float32List output, int frames) {
    final eng = _engine;
    if (eng == null || frames <= 0) return false;
    try {
      eng.process(input, output, frames);
      return true;
    } catch (e) {
      debugPrint('DSP processBuffer: $e');
      return false;
    }
  }

  void dispose() {
    try {
      _engine?.stop();
      _engine?.dispose();
    } catch (_) {}
    _engine = null;
    _available = false;
  }
}
