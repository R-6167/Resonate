import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_visualization_provider.dart';
import '../providers/music_provider.dart';

class AudioVisualizationWidget extends StatefulWidget {
  const AudioVisualizationWidget({Key? key}) : super(key: key);
  @override State<AudioVisualizationWidget> createState() => _AudioVisualizationWidgetState();
}

class _AudioVisualizationWidgetState extends State<AudioVisualizationWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AudioVisualizationProvider, MusicProvider>(builder: (context, settings, music, _) {
      if (!settings.enabled) return const Center(child: Text('Visualization Disabled'));
      return AnimatedBuilder(animation: _controller, builder: (_, __) => CustomPaint(
        painter: _VisualizationPainter(
          color: Theme.of(context).colorScheme.primary,
          phase: _controller.value * math.pi * 2,
          position: music.currentPosition.inMilliseconds / 1000.0,
          playing: music.isPlaying,
          type: settings.visualizationType,
          sensitivity: settings.sensitivity,
          mirror: settings.mirror,
          bass: settings.reactToBass,
        ),
        size: const Size(double.infinity, 180),
      ));
    });
  }
}

class _VisualizationPainter extends CustomPainter {
  final Color color;
  final double phase, position, sensitivity;
  final bool playing, mirror, bass;
  final String type;
  _VisualizationPainter({required this.color, required this.phase, required this.position, required this.playing, required this.type, required this.sensitivity, required this.mirror, required this.bass});

  @override
  void paint(Canvas canvas, Size size) {
    final bars = type == 'waveform' ? 48 : 28;
    final values = List<double>.generate(bars, (i) {
      final bassBoost = bass ? 1.0 + (1.0 - i / bars) * .45 : 1.0;
      final motion = playing ? math.sin(phase * 1.7 + i * .72 + position * 1.8).abs() : .08;
      return (.10 + motion * .80) * sensitivity * bassBoost;
    });
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color.withOpacity(.92)..strokeCap = StrokeCap.round;

    if (type == 'circular') {
      final radius = math.min(size.width, size.height) * .20;
      for (var i = 0; i < values.length; i++) {
        final angle = i / values.length * math.pi * 2;
        final r2 = radius + values[i] * radius * 1.6;
        canvas.drawLine(Offset(center.dx + math.cos(angle) * radius, center.dy + math.sin(angle) * radius), Offset(center.dx + math.cos(angle) * r2, center.dy + math.sin(angle) * r2), paint..strokeWidth = 3);
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
      if (mirror) { canvas.save(); canvas.translate(0, size.height); canvas.scale(1, -1); canvas.drawPath(path, paint..color = color.withOpacity(.25)); canvas.restore(); }
      return;
    }
    final width = size.width / values.length;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] * size.height * .78;
      final x = i * width + width / 2;
      canvas.drawLine(Offset(x, size.height * .92), Offset(x, size.height * .92 - h), paint..strokeWidth = math.max(2, width * .65));
    }
  }

  @override bool shouldRepaint(covariant _VisualizationPainter old) => true;
}
