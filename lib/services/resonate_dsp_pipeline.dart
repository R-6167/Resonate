import 'package:flutter/services.dart';
import 'dart:math' as math;

/// ---------------------------------------------------------------------------
/// Resonate original software EQ model (not Superpowered / not another app).
/// Peaking sections use public RBJ-style filter math; band plan + Q are ours.
/// ---------------------------------------------------------------------------

class ResonateBiquad {
  ResonateBiquad._(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0, b1, b2, a1, a2;

  factory ResonateBiquad.peaking({
    required double sampleRate,
    required double freqHz,
    required double gainDb,
    double q = 1.4,
  }) {
    final safeSr = sampleRate <= 0 ? 44100.0 : sampleRate;
    final f = freqHz.clamp(20.0, safeSr * 0.45);
    final a = math.pow(10.0, gainDb / 40.0).toDouble();
    final w0 = 2.0 * math.pi * f / safeSr;
    final alpha = math.sin(w0) / (2.0 * q.clamp(0.3, 8.0));
    final cosw = math.cos(w0);

    final b0 = 1.0 + alpha * a;
    final b1 = -2.0 * cosw;
    final b2 = 1.0 - alpha * a;
    final a0 = 1.0 + alpha / a;
    final a1 = -2.0 * cosw;
    final a2 = 1.0 - alpha / a;

    return ResonateBiquad._(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  double magnitudeDb(double sampleRate, double freqHz) {
    final w = 2.0 * math.pi * freqHz / sampleRate;
    final z1r = math.cos(w);
    final z1i = -math.sin(w);
    final z2r = math.cos(2 * w);
    final z2i = -math.sin(2 * w);

    final numR = b0 + b1 * z1r + b2 * z2r;
    final numI = b1 * z1i + b2 * z2i;
    final denR = 1.0 + a1 * z1r + a2 * z2r;
    final denI = a1 * z1i + a2 * z2i;
    final denMag2 = denR * denR + denI * denI;
    if (denMag2 < 1e-20) return 0.0;
    final re = (numR * denR + numI * denI) / denMag2;
    final im = (numI * denR - numR * denI) / denMag2;
    final mag = math.sqrt(re * re + im * im);
    if (mag < 1e-12) return -80.0;
    return 20.0 * math.log(mag) / math.ln10;
  }
}

class ResonateDspEngine {
  ResonateDspEngine({
    this.sampleRate = 44100.0,
    List<double>? centersHz,
  }) : centersHz = List<double>.unmodifiable(centersHz ?? defaultCentersHz);

  static const List<double> defaultCentersHz = [
    20, 25, 32, 40, 50, 63, 80, 100, 125, 160,
    200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
    2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000,
  ];

  final double sampleRate;
  final List<double> centersHz;
  final List<double> bandGainsDb = List<double>.filled(31, 0.0);

  void setBandGains(List<double> gainsDb) {
    for (var i = 0; i < bandGainsDb.length; i++) {
      bandGainsDb[i] = i < gainsDb.length ? gainsDb[i].clamp(-12.0, 12.0) : 0.0;
    }
  }

  double qForBand(int index) {
    final hz = centersHz[index.clamp(0, centersHz.length - 1)];
    if (hz < 100) return 0.9;
    if (hz < 500) return 1.2;
    if (hz < 4000) return 1.6;
    return 1.3;
  }

  List<ResonateBiquad> buildFilters() {
    final out = <ResonateBiquad>[];
    for (var i = 0; i < centersHz.length; i++) {
      final g = bandGainsDb[i];
      if (g.abs() < 0.05) continue;
      out.add(ResonateBiquad.peaking(
        sampleRate: sampleRate,
        freqHz: centersHz[i],
        gainDb: g,
        q: qForBand(i),
      ));
    }
    return out;
  }

  double responseDbAt(double freqHz) {
    var sum = 0.0;
    for (final f in buildFilters()) {
      sum += f.magnitudeDb(sampleRate, freqHz);
    }
    return sum.clamp(-18.0, 18.0);
  }

  List<double> responseAtCenters(List<double> hardwareCentersHz) {
    return [for (final hz in hardwareCentersHz) responseDbAt(hz)];
  }

  /// User-facing product name.
  static const String engineId = 'Resonate DSP Engine';
}

/// Studio curve → hardware EQ targets (native PCM processor comes later).
class ResonateDspPipeline {
  ResonateDspPipeline({ResonateDspEngine? engine})
      : engine = engine ?? ResonateDspEngine();

  final ResonateDspEngine engine;

  void updateStudioGains(List<double> gainsDb) {
    engine.setBandGains(gainsDb);
  }

  List<double> hardwareTargets(List<double> hardwareCenterHz) {
    return engine.responseAtCenters(hardwareCenterHz);
  }

  String get id => ResonateDspEngine.engineId;
}

/// Bridge to Android DynamicsProcessing (Resonate multi-band native stage).
class ResonateNativeDspBridge {
  static const MethodChannel _channel =
      MethodChannel('com.aetherion.resonate/audio_effects');

  static int? lastBandCount;
  static bool available = false;
  static String engineLabel = 'Resonate DSP Engine';

  static Future<bool> attachSession(int sessionId) async {
    if (sessionId <= 0) return false;
    try {
      final raw = await _channel.invokeMethod<dynamic>('attachResonateDsp', {
        'sessionId': sessionId,
      });
      if (raw is Map) {
        available = raw['ok'] == true;
        lastBandCount = (raw['bandCount'] as num?)?.toInt() ?? 0;
        // Always show product name in UI; ignore technical server strings.
        engineLabel = 'Resonate DSP Engine';
        return available;
      }
    } catch (_) {}
    available = false;
    return false;
  }

  /// Push studio centers/gains; native side maps onto its band count.
  static Future<bool> pushBands({
    required List<double> centersHz,
    required List<double> gainsDb,
    required bool enabled,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('setResonateEqBands', {
        'centersHz': centersHz,
        'gainsDb': gainsDb,
        'enabled': enabled,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setResonateDspEnabled', {'enabled': enabled});
    } catch (_) {}
  }
}
