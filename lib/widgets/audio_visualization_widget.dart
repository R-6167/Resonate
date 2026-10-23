import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_visualization_provider.dart';

/// Renders the shared native FFT feed directly.
///
/// There is deliberately no independent phase/timer animation here: bar height,
/// wave shape, and circular radius all come from measured spectrum values. That
/// keeps the visualizer from appearing alive when capture is silent or stale.
class AudioVisualizationWidget extends StatelessWidget {
  const AudioVisualizationWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioVisualizationProvider>(
      builder: (context, settings, _) {
        if (!settings.enabled) return const SizedBox(height: 180);

        return SizedBox(
          height: 180,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(
              key: const ValueKey('audio-spectrum-painter'),
              painter: _SpectrumPainter(
                color: Theme.of(context).colorScheme.primary,
                spectrum: List<double>.unmodifiable(settings.frequencies),
                type: settings.visualizationType,
                sensitivity: settings.sensitivity,
                smoothing: settings.smoothing,
                mirror: settings.mirror,
                emphasizeBass: settings.reactToBass,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter({
    required this.color,
    required this.spectrum,
    required this.type,
    required this.sensitivity,
    required this.smoothing,
    required this.mirror,
    required this.emphasizeBass,
  });

  final Color color;
  final List<double> spectrum;
  final String type;
  final double sensitivity;
  final double smoothing;
  final bool mirror;
  final bool emphasizeBass;

  List<double> _displayBands(int count) {
    if (spectrum.isEmpty) return List<double>.filled(count, 0);
    return List<double>.generate(count, (index) {
      final from = (index * spectrum.length / count).floor();
      final until = math.max(from + 1, ((index + 1) * spectrum.length / count).ceil());
      var peak = 0.0;
      for (var i = from; i < until && i < spectrum.length; i++) {
        final sample = spectrum[i].isFinite ? spectrum[i].clamp(0.0, 1.0) : 0.0;
        peak = math.max(peak, sample).toDouble();
      }
      // Android's FFT magnitudes are linear and typically small. The square
      // root makes quiet-but-real bands visible without fabricating motion.
      var level = math.sqrt(peak);
      level *= 0.45 + sensitivity * 1.25;
      if (emphasizeBass) {
        level *= 1 + (1 - index / count) * 0.35;
      }
      return level.clamp(0.0, 1.0).toDouble();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final count = type == 'waveform' || type == 'wave' ? 48 : 32;
    final levels = _displayBands(count);
    final hasSignal = spectrum.any((value) => value.isFinite && value > 0.012);
    final centerY = size.height / 2;
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    if (type == 'circular') {
      final radius = math.min(size.width, size.height) * 0.22;
      final maxLength = math.min(size.width, size.height) * 0.24;
      final paint = Paint()
        ..color = color.withValues(alpha: 0.9)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3;
      for (var i = 0; i < levels.length; i++) {
        final angle = i / levels.length * math.pi * 2;
        final length = hasSignal ? levels[i] * maxLength : 1.5;
        canvas.drawLine(
          Offset(size.width / 2 + math.cos(angle) * radius,
              centerY + math.sin(angle) * radius),
          Offset(size.width / 2 + math.cos(angle) * (radius + length),
              centerY + math.sin(angle) * (radius + length)),
          paint,
        );
      }
      canvas.drawCircle(
        Offset(size.width / 2, centerY),
        radius * 0.55,
        Paint()..color = color.withValues(alpha: 0.10),
      );
      return;
    }

    if (type == 'waveform' || type == 'wave') {
      // FFT magnitudes are an envelope, not signed PCM samples. Alternating
      // their sign made the old line jump above/below center at every band,
      // producing a jagged, hand-sketched look. Draw a smooth, mirrored
      // spectral ribbon instead, using quadratic midpoints for a calm curve.
      final upper = <Offset>[];
      final lower = <Offset>[];
      for (var i = 0; i < levels.length; i++) {
        final x = i / (levels.length - 1) * size.width;
        final amplitude = hasSignal
            ? levels[i] * size.height * (type == 'waveform' ? 0.27 : 0.20)
            : 0.0;
        upper.add(Offset(x, centerY - amplitude));
        lower.add(Offset(x, centerY + amplitude * (mirror ? 1.0 : 0.58)));
      }

      Path smoothCurve(List<Offset> points) {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (var i = 1; i < points.length; i++) {
          final previous = points[i - 1];
          final current = points[i];
          final midX = (previous.dx + current.dx) / 2;
          final midY = (previous.dy + current.dy) / 2;
          path.quadraticBezierTo(previous.dx, previous.dy, midX, midY);
          if (i == points.length - 1) {
            path.quadraticBezierTo(midX, midY, current.dx, current.dy);
          }
        }
        return path;
      }

      final topPath = smoothCurve(upper);
      final bottomPath = smoothCurve(lower);
      final ribbon = Path()
        ..addPath(topPath, Offset.zero)
        ..lineTo(lower.last.dx, lower.last.dy)
        ..addPath(bottomPath, Offset.zero);
      // Use a soft fill so the wave reads as a designed surface rather than
      // a single thin scribble. Keep all effects inexpensive on older devices.
      final fill = Path()..moveTo(upper.first.dx, upper.first.dy);
      fill.addPath(topPath, Offset.zero);
      fill.lineTo(lower.last.dx, lower.last.dy);
      for (var i = lower.length - 1; i >= 0; i--) {
        fill.lineTo(lower[i].dx, lower[i].dy);
      }
      fill.close();
      canvas.drawPath(
        fill,
        Paint()
          ..color = color.withValues(alpha: hasSignal ? 0.13 : 0.035)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        topPath,
        Paint()
          ..color = color.withValues(alpha: hasSignal ? 0.96 : 0.28)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2.4,
      );
      canvas.drawPath(
        bottomPath,
        Paint()
          ..color = color.withValues(alpha: hasSignal ? 0.46 : 0.14)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.7,
      );
      return;
    }

    final slotWidth = size.width / levels.length;
    final barPaint = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.0, slotWidth * 0.58).toDouble();
    for (var i = 0; i < levels.length; i++) {
      final height = hasSignal ? levels[i] * size.height * 0.72 : 2.0;
      final x = (i + 0.5) * slotWidth;
      final baseline = mirror ? size.height * 0.78 : size.height * 0.90;
      canvas.drawLine(
        Offset(x, baseline),
        Offset(x, baseline - height),
        barPaint,
      );
      if (mirror) {
        canvas.drawLine(
          Offset(x, baseline + 2),
          Offset(x, baseline + height * 0.48),
          barPaint..color = color.withValues(alpha: 0.24),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    if (oldDelegate.color != color ||
        oldDelegate.type != type ||
        oldDelegate.sensitivity != sensitivity ||
        oldDelegate.smoothing != smoothing ||
        oldDelegate.mirror != mirror ||
        oldDelegate.emphasizeBass != emphasizeBass ||
        oldDelegate.spectrum.length != spectrum.length) {
      return true;
    }
    for (var i = 0; i < spectrum.length; i++) {
      if (oldDelegate.spectrum[i] != spectrum[i]) return true;
    }
    return false;
  }
}
