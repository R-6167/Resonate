import 'resonate_biquad.dart';

/// Resonate-owned multi-band software EQ model.
///
/// Design goals (original to this project):
/// - 31 fixed centers (ISO-ish) as the control surface
/// - Peaking sections with bandwidth that scales mildly with frequency
/// - Cascaded response used to drive whatever output path is available
///   (Android hardware EQ bands today; native sample processor later)
///
/// This is not a port of Superpowered, Musicolet, or any other player DSP.
class ResonateDspEngine {
  ResonateDspEngine({
    this.sampleRate = 44100.0,
    List<double>? centersHz,
  }) : centersHz = List<double>.unmodifiable(
          centersHz ?? defaultCentersHz,
        );

  /// Default 31-band layout used by Resonate studio EQ.
  static const List<double> defaultCentersHz = [
    20, 25, 32, 40, 50, 63, 80, 100, 125, 160,
    200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
    2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000,
  ];

  final double sampleRate;
  final List<double> centersHz;

  /// Gain per studio band (dB), same length as [centersHz].
  final List<double> bandGainsDb = List<double>.filled(31, 0.0);

  void setBandGains(List<double> gainsDb) {
    for (var i = 0; i < bandGainsDb.length; i++) {
      bandGainsDb[i] = i < gainsDb.length ? gainsDb[i].clamp(-12.0, 12.0) : 0.0;
    }
  }

  /// Q increases slightly in the midrange for clearer vocal/instrument control.
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

  /// Total cascade magnitude at [freqHz] in dB.
  double responseDbAt(double freqHz) {
    final filters = buildFilters();
    var sum = 0.0;
    for (final f in filters) {
      sum += f.magnitudeDb(sampleRate, freqHz);
    }
    return sum.clamp(-18.0, 18.0);
  }

  /// Sample the model at arbitrary hardware center frequencies.
  List<double> responseAtCenters(List<double> hardwareCentersHz) {
    return [for (final hz in hardwareCentersHz) responseDbAt(hz)];
  }

  /// Identity string for diagnostics / About (Resonate original).
  static const String engineId = 'ResonateDSP/v1-peak31';
}
