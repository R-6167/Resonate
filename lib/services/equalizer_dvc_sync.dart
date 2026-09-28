import 'package:flutter/foundation.dart';

import 'audio_effects_bridge.dart';
import 'dsp_engine_bridge.dart';

/// Keeps DSP ENGINE Direct Volume Control aligned with EQ preamp.
///
/// 1) Offline / control-path Dart [DspEngineBridge] (FFI package)
/// 2) Live per-stream engines on the ExoPlayer sinks (MethodChannel → registry)
void syncPreampToDvc(double preampDb, {bool enabled = true}) {
  final db = enabled ? preampDb.clamp(-12.0, 12.0) : 0.0;
  DspEngineBridge.instance.setVolumeRampedDb(db.toDouble());
  // Live path: both A and B handles (sticky if engines not up yet).
  AudioEffectsBridge.setLiveDspPreampDb(db.toDouble()).then((r) {
    if (r != null) {
      debugPrint('live DVC preamp db=$db active=${r['active']}');
    }
  }).catchError((_) {});
}

/// Push studio multi-band curve into native DSP ENGINE EQ (offline + live).
void syncStudioBandsToNativeEq({
  required List<double> centersHz,
  required List<double> gainsDb,
  required bool enabled,
}) {
  DspEngineBridge.instance.setEqBands(
    centersHz: centersHz,
    gainsDb: gainsDb,
    enabled: enabled,
  );
  AudioEffectsBridge.setLiveDspEqBands(
    centersHz: centersHz,
    gainsDb: gainsDb,
    enabled: enabled,
  ).then((r) {
    if (r != null) {
      debugPrint(
        'live EQ bands=${gainsDb.length} enabled=$enabled active=${r['active']}',
      );
    }
  }).catchError((_) {});
}

Future<bool> ensureDspEngineForEq() {
  return DspEngineBridge.instance.ensureInitialized();
}
