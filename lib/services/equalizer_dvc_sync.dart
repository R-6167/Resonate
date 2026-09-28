import 'dsp_engine_bridge.dart';

/// Keeps DSP ENGINE Direct Volume Control aligned with EQ preamp.
void syncPreampToDvc(double preampDb, {bool enabled = true}) {
  final db = enabled ? preampDb.clamp(-6.0, 6.0) : 0.0;
  DspEngineBridge.instance.setVolumeRampedDb(db.toDouble());
}

/// Push studio multi-band curve into native DSP ENGINE EQ.
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
}

Future<bool> ensureDspEngineForEq() {
  return DspEngineBridge.instance.ensureInitialized();
}
