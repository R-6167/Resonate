import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_visualization_provider.dart';
import '../providers/music_provider.dart';

class AudioVisualizationWidget extends StatelessWidget {
  const AudioVisualizationWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer3<AudioVisualizationProvider, MusicProvider, _VisualizationClock>(
      builder: (context, settings, music, clock, _) {
        if (!settings.enabled) {
          return const Center(child: Text('Visualization Disabled'));
        }
        return CustomPaint(
          painter: _VisualizationPainter(
            phase: clock.phase,
            position: music.currentPosition.inMilliseconds / 1000.0,
            playing: music.isPlaying,
            type: settings.visualizationType,
            sensitivity: settings.sensitivity,
            mirror: settings.mirror,
            bass: settings.reactToBass,
          ),
          size: const Size(double.infinity, 180),
        );
      },
    );
  }
}

class _VisualizationClock extends ChangeNotifier {
  double phase = 0;
  _VisualizationClock() {
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      phase = (phase + 0.12) % (math.pi * 2);
      notifyListeners();
      return true;
    });
  }
}

class _VisualizationPainter extends CustomPainter {
  final double phase;
  final double position;
  final bool playing;
  final String type;
  final double sensitivity;
  final bool mirror;
  final bool bass;

  _VisualizationPainter({required this.phase, required this.position, required this.playing, required this.type, required this.sensitivity, required this.mirror, required this.bass});

  @override
  void paint(Canvas canvas, Size size) {
    final color = Colors.white.withOpacity(0.92);
    final bars = type == 'waveform' ? 48 : 28;
    final values = List<double>.generate(bars, (i) {
      final bassBoost = bass ? (1.0 + (1.0 - i / bars) * 0.45) : 1.0;
      final motion = playing ? math.sin(phase * 1.7 + i * 0.72 + position * 1.8).abs() : 0.10;
      return (0.10 + motion * 0.80) * sensitivity * bassBoost;
    });
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color..strokeCap = StrokeCap.round;

    if (type == 'circular') {
      final radius = math.min(size.width, size.height) * .20;
      for (var i = 0; i < values.length; i++) {
        final angle = i / values.length * math.pi * 2;
        final r1 = radius;
        final r2 = radius + values[i] * radius * 1.6;
        canvas.drawLine(Offset(center.dx + math.cos(angle) * r1, center.dy + math.sin(angle) * r1), Offset(center.dx + math.cos(angle) * r2, center.dy + math.sin(angle) * r2), paint..strokeWidth = 3);
      }
      canvas.drawCircle(center, radius * .42, Paint()..color = color.withOpacity(.12));
      return;
    }

    if (type == 'waveform' || type == 'wave') {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = i / (values.length - 1) * size.width;
        final y = center.dy + math.sin(i * .55 + phase + position * 2) * values[i] * size.height * .30;
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      canvas.drawPath(path, paint..style = PaintingStyle.stroke..strokeWidth = 2.5);
      if (mirror) {
        canvas.save(); canvas.translate(0, size.height); canvas.scale(1, -1); canvas.drawPath(path, paint..color = color.withOpacity(.25)); canvas.restore();
      }
      return;
    }

    final width = size.width / values.length;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] * size.height * .78;
      final x = i * width + width / 2;
      canvas.drawLine(Offset(x, size.height * .92), Offset(x, size.height * .92 - h), paint..strokeWidth = math.max(2, width * .65));
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizationPainter old) => old.phase != phase || old.position != position || old.playing != playing || old.type != type || old.sensitivity != sensitivity || old.mirror != mirror;
}
