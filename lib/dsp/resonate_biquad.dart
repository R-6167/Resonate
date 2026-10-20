import 'dart:math' as math;

/// One peaking (bell) equalizer section used by the Resonate software EQ model.
///
/// Coefficients follow the public RBJ audio EQ cookbook (widely published
/// filter design math — not taken from any music app). Resonate owns the
/// band layout, Q choices, pipeline order, and how results are applied.
class ResonateBiquad {
  ResonateBiquad._(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0, b1, b2, a1, a2;

  /// Peaking EQ at [freqHz] with gain [gainDb] and quality [q].
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

  /// Complex frequency response magnitude in dB at [freqHz].
  double magnitudeDb(double sampleRate, double freqHz) {
    final w = 2.0 * math.pi * freqHz / sampleRate;
    final z1r = math.cos(w);
    final z1i = -math.sin(w);
    final z2r = math.cos(2 * w);
    final z2i = -math.sin(2 * w);

    // H = (b0 + b1 z^-1 + b2 z^-2) / (1 + a1 z^-1 + a2 z^-2)
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
