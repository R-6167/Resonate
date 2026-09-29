import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'audio_effects_bridge.dart';
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
class DspProcessPath {
  DspProcessPath._();
  static final DspProcessPath instance = DspProcessPath._();

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
    final w = 2 * math.pi * 1000.0 / sampleRate;
    for (var i = 0; i < frames; i++) {
      final s = 0.25 * math.sin(w * i);
      input[i * 2] = s;
      input[i * 2 + 1] = s;
    }

    double rms(Float32List x) {
      var a = 0.0;
      for (final v in x) {
        a += v * v;
      }
      return math.sqrt(a / x.length);
    }

    final inRms = rms(input);
    final ok = bridge.processBuffer(input, output, frames);
    if (!ok) {
      return DspProcessPathStatus(
        engineLoaded: true,
        processOk: false,
        version: bridge.version,
        detail: 'processBuffer returned false',
        inputRmsDb: 20 * math.log(inRms + 1e-12) / math.ln10,
      );
    }
    final outRms = rms(output);
    final inDb = 20 * math.log(inRms + 1e-12) / math.ln10;
    final outDb = 20 * math.log(outRms + 1e-12) / math.ln10;
    return DspProcessPathStatus(
      engineLoaded: true,
      processOk: true,
      version: bridge.version,
      inputRmsDb: inDb,
      outputRmsDb: outDb,
    );
  }

  /// Aggressive offline bass stress (native true-peak path).
  Future<Map<String, dynamic>> runBassStressHarness() async {
    final raw = await AudioEffectsBridge.runBassStress();
    if (raw == null) {
      return {
        'ok': false,
        'detail': 'native stress unavailable',
      };
    }
    return raw;
  }
}
