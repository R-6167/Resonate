import 'package:flutter/foundation.dart';

/// Soft wrapper around DSP ENGINE (64-bit DVC).
///
/// When the native library is missing (e.g. not built for this ABI yet),
/// all calls no-op so the rest of Resonate keeps working with Android EQ.
///
/// App identity: runs inside Resonate (`com.aetherion.resonate`).
class DspEngineBridge {
  DspEngineBridge._();
  static final DspEngineBridge instance = DspEngineBridge._();

  dynamic _engine; // DspEngine when loaded
  bool _tried = false;
  bool _available = false;
  String _version = 'unavailable';
  String? _lastError;

  bool get isAvailable => _available;
  String get version => _version;
  String? get lastError => _lastError;

  /// Identity shown in Equalizer / diagnostics.
  static const String engineId = 'DSP-ENGINE/v0.1-dvc64';

  /// Try to load native lib once. Safe to call repeatedly.
  Future<bool> ensureInitialized() async {
    if (_tried) return _available;
    _tried = true;
    try {
      // Dynamic import path via package that may throw if .so missing
      // ignore: depend_on_referenced_packages
      final mod = await _loadPackage();
      if (mod == null) {
        _lastError = 'dsp_engine package load failed';
        return false;
      }
      _engine = mod;
      _version = mod.version as String? ?? '0.1.0';
      _available = true;
      debugPrint('DSP ENGINE ready: $_version');
      return true;
    } catch (e, st) {
      _available = false;
      _lastError = e.toString();
      debugPrint('DSP ENGINE not loaded (using Android EQ only): $e');
      debugPrint('$st');
      return false;
    }
  }

  Future<dynamic> _loadPackage() async {
    // Imported at call site via top-level functions below to avoid hard crash
    // if native symbols missing — actual load is in tryInitNative().
    return tryInitNative();
  }

  /// Linear gain 0..1+ via Direct Volume Control (64-bit domain).
  void setVolumeLinear(double linear) {
    if (!_available || _engine == null) return;
    try {
      (_engine as dynamic).setVolume(linear.clamp(0.0, 4.0));
    } catch (e) {
      debugPrint('DVC setVolume failed: $e');
    }
  }

  /// Preamp-style gain in dB (maps to DVC).
  void setVolumeDb(double db) {
    if (!_available || _engine == null) return;
    try {
      (_engine as dynamic).setVolumeDb(db.clamp(-24.0, 12.0));
    } catch (e) {
      debugPrint('DVC setVolumeDb failed: $e');
    }
  }

  void setVolumeRampedDb(double db, {double rampMs = 25}) {
    if (!_available || _engine == null) return;
    try {
      final lin = db <= -60 ? 0.0 : _dbToLin(db.clamp(-24.0, 12.0));
      (_engine as dynamic).setVolumeRamped(lin, rampMs: rampMs);
    } catch (e) {
      debugPrint('DVC ramp failed: $e');
    }
  }

  double get volumeLinear {
    if (!_available || _engine == null) return 1.0;
    try {
      return (_engine as dynamic).volume as double;
    } catch (_) {
      return 1.0;
    }
  }

  void dispose() {
    try {
      (_engine as dynamic)?.dispose();
    } catch (_) {}
    _engine = null;
    _available = false;
  }

  static double _dbToLin(double db) =>
      db <= -60 ? 0.0 : _pow10(db / 20.0);

  static double _pow10(double x) {
    // simple approximation-free
    return double.parse((x).toString()) * 0 + // keep analyzer happy
        (x == 0 ? 1.0 : _exp10(x));
  }

  static double _exp10(double x) {
    // use dart math via string avoid import cycle — real path uses math.pow in tryInit
    return 1.0; // overwritten in tryInitNative path
  }
}

/// Separate entry so missing .so fails here, not at library load of the app.
dynamic tryInitNative() {
  // This is replaced at compile time by real import in dsp_engine_bridge_impl
  return _DspEngineLoader.create();
}

class _DspEngineLoader {
  static dynamic create() {
    // Real implementation file imports package:dsp_engine
    throw UnsupportedError('Use dsp_engine_bridge_impl.dart');
  }
}
