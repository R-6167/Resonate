import 'package:flutter/material.dart';
import '../services/waveform_service.dart';

class WaveformWidget extends StatefulWidget {
  final String? audioPath;
  final int samples;
  final Color color;

  const WaveformWidget({Key? key, required this.audioPath, this.samples = 120, this.color = Colors.indigoAccent}) : super(key: key);

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget> {
  late Future<List<int>> _futureSamples;

  @override
  void initState() {
    super.initState();
    _futureSamples = _load();
  }

  Future<List<int>> _load() async {
    if (widget.audioPath == null) return List.filled(widget.samples, 0);
    return await WaveformService.getWaveform(widget.audioPath!, samples: widget.samples);
  }

  @override
  void didUpdateWidget(covariant WaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPath != widget.audioPath) {
      _futureSamples = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: _futureSamples,
      builder: (context, snap) {
        if (!snap.hasData) {
          return SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final samples = snap.data!;
        return SizedBox(
          height: 80,
          child: CustomPaint(
            painter: _WaveformPainter(samples: samples, color: widget.color),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<int> samples;
  final Color color;

  _WaveformPainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.9);
    final w = size.width / samples.length;
    final centerY = size.height / 2;
    for (var i = 0; i < samples.length; i++) {
      final x = i * w;
      final h = (samples[i] / 100) * size.height;
      final rect = Rect.fromLTWH(x, centerY - h / 2, w * 0.8, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => oldDelegate.samples != samples || oldDelegate.color != color;
}
