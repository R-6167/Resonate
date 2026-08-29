import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_visualization_provider.dart';
import '../models/audio_visualization.dart';

// Bar Visualization Widget
class BarVisualization extends StatelessWidget {
  final List<double> frequencies;
  const BarVisualization({Key? key, required this.frequencies}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: BarVisualizationPainter(
        frequencies: frequencies,
        color: Theme.of(context).primaryColor,
      ),
      size: const Size(double.infinity, 200),
    );
  }
}

class BarVisualizationPainter extends CustomPainter {
  final List<double> frequencies;
  final Color color;

  BarVisualizationPainter({
    required this.frequencies,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / frequencies.length;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < frequencies.length; i++) {
      final height = frequencies[i] * size.height;
      final x = i * barWidth + barWidth / 2;
      final y = size.height;

      // Draw bar
      canvas.drawLine(
        Offset(x, y),
        Offset(x, y - height),
        paint..strokeWidth = barWidth * 0.7,
      );

      // Draw reflection
      canvas.drawLine(
        Offset(x, y),
        Offset(x, y + height * 0.3),
        paint..strokeWidth = barWidth * 0.7..color = color.withOpacity(0.3),
      );
    }
  }

  @override
  bool shouldRepaint(BarVisualizationPainter oldDelegate) => true;
}

// Circular Visualization Widget
class CircularVisualization extends StatelessWidget {
  final List<double> frequencies;
  const CircularVisualization({Key? key, required this.frequencies})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CircularVisualizationPainter(
        frequencies: frequencies,
        color: Theme.of(context).primaryColor,
      ),
      size: const Size(double.infinity, 250),
    );
  }
}

class CircularVisualizationPainter extends CustomPainter {
  final List<double> frequencies;
  final Color color;

  CircularVisualizationPainter({
    required this.frequencies,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.height / 3;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Draw circles for each frequency band
    for (int i = 0; i < frequencies.length; i++) {
      final angle = (2 * 3.14159 * i) / frequencies.length;
      final radius = baseRadius + (frequencies[i] * baseRadius);

      if (i == 0) {
        canvas.drawCircle(center, radius, paint);
      } else {
        final prevAngle = (2 * 3.14159 * (i - 1)) / frequencies.length;
        final prevRadius =
            baseRadius + (frequencies[i - 1] * baseRadius);

        final startAngle = prevAngle;
        final endAngle = angle;

        final path = Path();
        path.moveTo(
          center.dx + prevRadius * cosAngle(prevAngle),
          center.dy + prevRadius * sinAngle(prevAngle),
        );
        path.lineTo(
          center.dx + radius * cosAngle(angle),
          center.dy + radius * sinAngle(angle),
        );

        canvas.drawPath(path, paint);
      }
    }

    // Draw center circle
    canvas.drawCircle(
      center,
      baseRadius * 0.3,
      paint..style = PaintingStyle.fill..color = color.withOpacity(0.2),
    );
  }

  double cosAngle(double angle) => (angle).cos();
  double sinAngle(double angle) => (angle).sin();

  @override
  bool shouldRepaint(CircularVisualizationPainter oldDelegate) => true;
}

// Waveform Visualization Widget
class WaveformVisualization extends StatelessWidget {
  final List<double> frequencies;
  const WaveformVisualization({Key? key, required this.frequencies})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WaveformVisualizationPainter(
        frequencies: frequencies,
        color: Theme.of(context).primaryColor,
      ),
      size: const Size(double.infinity, 150),
    );
  }
}

class WaveformVisualizationPainter extends CustomPainter {
  final List<double> frequencies;
  final Color color;

  WaveformVisualizationPainter({
    required this.frequencies,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final centerY = size.height / 2;
    final pointWidth = size.width / frequencies.length;

    for (int i = 0; i < frequencies.length; i++) {
      final x = i * pointWidth;
      final y = centerY - (frequencies[i] * centerY);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Draw reflection
    final reflectionPaint = paint..color = color.withOpacity(0.2);
    final reflectionPath = Path();

    for (int i = 0; i < frequencies.length; i++) {
      final x = i * pointWidth;
      final y = centerY + (frequencies[i] * centerY * 0.5);

      if (i == 0) {
        reflectionPath.moveTo(x, y);
      } else {
        reflectionPath.lineTo(x, y);
      }
    }

    canvas.drawPath(reflectionPath, reflectionPaint);
  }

  @override
  bool shouldRepaint(WaveformVisualizationPainter oldDelegate) => true;
}

// Dots Visualization Widget
class DotsVisualization extends StatelessWidget {
  final List<double> frequencies;
  const DotsVisualization({Key? key, required this.frequencies})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DotsVisualizationPainter(
        frequencies: frequencies,
        color: Theme.of(context).primaryColor,
      ),
      size: const Size(double.infinity, 200),
    );
  }
}

class DotsVisualizationPainter extends CustomPainter {
  final List<double> frequencies;
  final Color color;

  DotsVisualizationPainter({
    required this.frequencies,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotWidth = size.width / frequencies.length;
    final centerY = size.height / 2;

    for (int i = 0; i < frequencies.length; i++) {
      final x = i * dotWidth + dotWidth / 2;
      final radius = (frequencies[i] * 15).clamp(2.0, 20.0);

      final paint = Paint()
        ..color = color.withOpacity(frequencies[i].clamp(0.2, 1.0))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, centerY), radius, paint);
    }
  }

  @override
  bool shouldRepaint(DotsVisualizationPainter oldDelegate) => true;
}

// Wave Animation Widget
class WaveAnimationVisualization extends StatefulWidget {
  final List<double> frequencies;
  const WaveAnimationVisualization({Key? key, required this.frequencies})
      : super(key: key);

  @override
  State<WaveAnimationVisualization> createState() =>
      _WaveAnimationVisualizationState();
}

class _WaveAnimationVisualizationState extends State<WaveAnimationVisualization>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: WaveAnimationPainter(
            frequencies: widget.frequencies,
            color: Theme.of(context).primaryColor,
            animationValue: _controller.value,
          ),
          size: const Size(double.infinity, 200),
        );
      },
    );
  }
}

class WaveAnimationPainter extends CustomPainter {
  final List<double> frequencies;
  final Color color;
  final double animationValue;

  WaveAnimationPainter({
    required this.frequencies,
    required this.color,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final centerY = size.height / 2;
    final pointWidth = size.width / frequencies.length;

    for (int i = 0; i < frequencies.length; i++) {
      final x = i * pointWidth;
      final waveOffset = 20 * (frequencies[i]).sin() * animationValue;
      final y = centerY - (frequencies[i] * centerY) + waveOffset;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.quadraticBezierTo(
          x - pointWidth / 2,
          y,
          x,
          y,
        );
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WaveAnimationPainter oldDelegate) => true;
}

// Main Audio Visualization Widget
class AudioVisualizationWidget extends StatelessWidget {
  const AudioVisualizationWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioVisualizationProvider>(
      builder: (context, vizProvider, _) {
        if (!vizProvider.enabled) {
          return Container(
            height: 200,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'Visualization Disabled',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        Widget visualization;
        switch (vizProvider.visualizationType) {
          case 'bars':
            visualization = BarVisualization(frequencies: vizProvider.frequencies);
            break;
          case 'circular':
            visualization = CircularVisualization(frequencies: vizProvider.frequencies);
            break;
          case 'waveform':
            visualization = WaveformVisualization(frequencies: vizProvider.frequencies);
            break;
          case 'dots':
            visualization = DotsVisualization(frequencies: vizProvider.frequencies);
            break;
          case 'wave':
            visualization = WaveAnimationVisualization(frequencies: vizProvider.frequencies);
            break;
          default:
            visualization = BarVisualization(frequencies: vizProvider.frequencies);
        }

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).primaryColor.withOpacity(0.2),
            ),
          ),
          child: visualization,
        );
      },
    );
  }
}
