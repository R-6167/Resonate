import 'package:flutter/foundation.dart';

import 'audio_effects_bridge.dart';

/// Keeps live DSP ENGINE Direct Volume Control aligned with EQ preamp.
///
/// Live path only (MethodChannel → DspEngineRegistry on A/B sinks).
/// Offline FFI package is optional and not required on dj_Mode.
void syncPreampToDvc(double preampDb, {bool enabled = true}) {
  final db = enabled ? preampDb.clamp(-12.0, 12.0) : 0.0;
  AudioEffectsBridge.setLiveDspPreampDb(db.toDouble()).then((r) {
    if (r != null) {
      debugPrint('live DVC preamp db=$db active=${r['active']}');
    }
  }).catchError((_) {});
}

/// Push studio multi-band curve into live native DSP ENGINE EQ (A/B).
void syncStudioBandsToNativeEq({
  required List<double> centersHz,
  required List<double> gainsDb,
  required bool enabled,
}) {
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

/// Apply speaker-protection policy from [AudioOutputRouteService].
void syncSpeakerPolicy({
  required bool needsSpeakerProtection,
  double virtualBassAmount = 0.55,
}) {
  AudioEffectsBridge.setLiveDspSpeakerMode(needsSpeakerProtection)
      .then((r) {
    if (r != null) {
      debugPrint(
        'live speakerMode=$needsSpeakerProtection active=${r['active']}',
      );
    }
  }).catchError((_) {});

  final amount = needsSpeakerProtection ? virtualBassAmount.clamp(0.0, 1.0) : 0.0;
  AudioEffectsBridge.setLiveDspVirtualBass(amount).then((r) {
    if (r != null) {
      debugPrint('live virtualBass=$amount');
    }
  }).catchError((_) {});
}
