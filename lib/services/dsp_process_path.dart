import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'dsp_engine_bridge.dart';

/// Status of the native process path (not the live ExoPlayer sink).
class DspProcessPathStatus {
  final bool engineLoaded;
  final bool processOk;
  final String version;
  final String? detail;
  final double? inputRmsDb;
  final double? outputRmsDb;

  const DspProcessPathStatus({
    required this.engineLoaded,
    required this.processOk,
    required this.version,
    this.detail,
    this.inputRmsDb,
    this.outputRmsDb,
  });

  String get summary {
    if (!engineLoaded) return 'DSP ENGINE .so not loaded';
    if (!processOk) return detail ?? 'process() failed';
    final inDb = inputRmsDb?.toStringAsFixed(1) ?? '?';
    final outDb = outputRmsDb?.toStringAsFixed(1) ?? '?';
    return 'process() OK · in $inDb dB → out $outDb dB · $version';
  }
}

/// Offline / diagnostic use of DSP ENGINE [process].
///
/// **Live playback** still uses AndroidEqualizer + optional DynamicsProcessing.
/// A true custom ExoPlayer AudioSink needs a just_audio fork or custom media3
/// RenderersFactory — not available from app code alone.
class DspProcessPath {
  DspProcessPath._();
  static final DspProcessPath instance = DspProcessPath._();

  /// Process interleaved float32 PCM (writes [output]). Offline / tests only.
  bool processInterleaved({
    required Float32List input,
    required Float32List output,
    required int frames,
  }) {
    return DspEngineBridge.instance.processBuffer(input, output, frames);
  }

  /// Self-test: 1 kHz sine through EQ+DVC; returns RMS before/after.
  Future<DspProcessPathStatus> runSelfTest({
    int sampleRate = 48000,
    int frames = 2048,
    double boostDb = 6.0,
  }) async {
    final okInit = await DspEngineBridge.instance.ensureInitialized();
    if (!okInit) {
      return DspProcessPathStatus(
        engineLoaded: false,
        processOk: false,
        version: DspEngineBridge.instance.version,
        detail: DspEngineBridge.instance.lastError ?? 'init failed',
      );
    }

    final bridge = DspEngineBridge.instance;
    bridge.setEqBands(
      centersHz: List<double>.generate(31, (i) {
        const minF = 20.0;
        const maxF = 20000.0;
        return minF * math.pow(maxF / minF, i / 30.0);
      }),
      gainsDb: List<double>.generate(31, (i) {
        if (i >= 14 && i <= 18) return boostDb;
        return 0.0;
      }),
      enabled: true,
    );
    bridge.setVolumeLinear(1.0);

    final input = Float32List(frames * 2);
    final output = Float32List(frames * 2);
    final w = 2.0 * math.pi * 1000.0 / sampleRate;
    for (var i = 0; i < frames; i++) {
      final s = 0.25 * math.sin(w * i);
      input[i * 2] = s;
      input[i * 2 + 1] = s;
    }

    final processed = bridge.processBuffer(input, output, frames);
    if (!processed) {
      return DspProcessPathStatus(
        engineLoaded: true,
        processOk: false,
        version: bridge.version,
        detail: 'processBuffer returned false',
      );
    }

    double rms(Float32List x) {
      var sum = 0.0;
      for (final v in x) {
        sum += v * v;
      }
      final m = sum / x.length;
      if (m <= 1e-20) return -100.0;
      return 10.0 * math.log(m) / math.ln10;
    }

    final inDb = rms(input);
    final outDb = rms(output);
    debugPrint(
      'DSP process self-test: in=${inDb.toStringAsFixed(2)} dB '
      'out=${outDb.toStringAsFixed(2)} dB version=${bridge.version}',
    );

    return DspProcessPathStatus(
      engineLoaded: true,
      processOk: true,
      version: bridge.version,
      inputRmsDb: inDb,
      outputRmsDb: outDb,
    );
  }
}
