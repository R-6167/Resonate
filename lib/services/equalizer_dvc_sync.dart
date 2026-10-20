import 'package:flutter/foundation.dart';

import 'audio_effects_bridge.dart';
import 'audio_output_route.dart';

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

/// Apply speaker-protection + virtual-bass policy from output route.
///
/// [needsSpeakerProtection] enables the live engine speaker-safe path (limiting
/// LF boost that tears phone transducers). Virtual bass is route-dependent:
/// strong on phone speaker, light on headphones, off in car.
void syncSpeakerPolicy({
  required bool needsSpeakerProtection,
  double? virtualBassAmount,
  AudioOutputRoute? route,
}) {
  final resolvedRoute = route ?? AudioOutputRouteService.instance.route;
  final amount = (virtualBassAmount ??
          AudioOutputRouteService.instance.suggestedVirtualBass)
      .clamp(0.0, 1.0)
      .toDouble();

  // Speaker-safe mode only when playing through the built-in speaker (or unknown).
  AudioEffectsBridge.setLiveDspSpeakerMode(needsSpeakerProtection)
      .then((r) {
    if (r != null) {
      debugPrint(
        'live speakerMode=$needsSpeakerProtection '
        'route=${resolvedRoute.name} active=${r['active']}',
      );
    }
  }).catchError((e) {
    debugPrint('syncSpeakerPolicy speakerMode failed: $e');
  });

  // Virtual bass: keep amount 0 when policy says no protection *and* route is car,
  // otherwise use the provided/suggested amount (headphones get a light lift).
  final bass = needsSpeakerProtection
      ? amount
      : (resolvedRoute == AudioOutputRoute.car ? 0.0 : amount);

  AudioEffectsBridge.setLiveDspVirtualBass(bass).then((r) {
    if (r != null) {
      debugPrint('live virtualBass=$bass route=${resolvedRoute.name}');
    }
  }).catchError((e) {
    debugPrint('syncSpeakerPolicy virtualBass failed: $e');
  });
}
