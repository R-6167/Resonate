import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_visualization_provider.dart';
import '../providers/music_provider.dart';

class AudioVisualizationWidget extends StatefulWidget {
  const AudioVisualizationWidget({Key? key}) : super(key: key);
  @override State<AudioVisualizationWidget> createState() => _AudioVisualizationWidgetState();
}

class _AudioVisualizationWidgetState extends State<AudioVisualizationWidget> {
  Timer? _timer;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  MusicProvider? _music;
  bool _playing = false;
  double _fps = 24;
  bool _smoothAnimation = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final music = context.read<MusicProvider>();
    if (_music != music) {
      _music?.removeListener(_syncPlayback);
      _music = music;
      _music!.addListener(_syncPlayback);
    }
    final settings = context.read<AudioVisualizationProvider>();
    _fps = settings.frameRate;
    _smoothAnimation = settings.smoothAnimation;
    _playing = music.isPlaying;
    _restartTimer();
  }

  void _syncPlayback() {
    if (!mounted) return;
    final playing = _music?.isPlaying == true;
    if (_playing != playing) { _playing = playing; _restartTimer(); }
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!_playing || !_smoothAnimation) return;
    final milliseconds = (1000 / _fps.clamp(12, 30)).round().clamp(33, 83);
    _timer = Timer.periodic(Duration(milliseconds: milliseconds), (_) => _phase.value = (_phase.value + .055) % 1.0);
  }

  @override
  void dispose() { _music?.removeListener(_syncPlayback); _timer?.cancel(); _phase.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Consumer2<AudioVisualizationProvider, MusicProvider>(builder: (context, settings, music, _) {
    if (settings.frameRate != _fps || settings.smoothAnimation != _smoothAnimation) { _fps = settings.frameRate; _smoothAnimation = settings.smoothAnimation; WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _restartTimer(); }); }
    if (!settings.enabled) return const Center(child: Text('Visualization Disabled'));
    return ValueListenableBuilder<double>(valueListenable: _phase, builder: (_, phase, __) => CustomPaint(painter: _VisualizationPainter(color: Theme.of(context).colorScheme.primary, phase: phase * math.pi * 2, position: music.currentPosition.inMilliseconds / 1000.0, playing: music.isPlaying, type: settings.visualizationType, sensitivity: settings.sensitivity, mirror: settings.mirror, bass: settings.reactToBass, spectrum: settings.frequencies), size: const Size(double.infinity, 180)));
  });
}

class _VisualizationPainter extends CustomPainter {
  final Color color; final double phase, position, sensitivity; final bool playing, mirror, bass; final String type; final List<double> spectrum;
  _VisualizationPainter({required this.color, required this.phase, required this.position, required this.playing, required this.type, required this.sensitivity, required this.mirror, required this.bass, required this.spectrum});
  @override void paint(Canvas canvas, Size size) {
    final bars = type == 'waveform' ? 48 : 28;
    final values = List<double>.generate(bars, (i) {
      final index = ((i / bars) * spectrum.length).floor().clamp(0, math.max(0, spectrum.length - 1)).toInt();
      final measured = spectrum.isEmpty ? 0.0 : spectrum[index].clamp(0.0, 1.0).toDouble();
      final bassBoost = bass ? 1.0 + (1.0 - i / bars) * .45 : 1.0;
      return (measured * (0.55 + sensitivity * 1.15) * bassBoost).clamp(0.0, 1.0).toDouble();
    });
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color.withOpacity(.92)..strokeCap = StrokeCap.round;
    if (type == 'circular') { final radius = math.min(size.width, size.height) * .20; for (var i = 0; i < values.length; i++) { final angle = i / values.length * math.pi * 2; final r2 = radius + values[i] * radius * 1.6; canvas.drawLine(Offset(center.dx + math.cos(angle) * radius, center.dy + math.sin(angle) * radius), Offset(center.dx + math.cos(angle) * r2, center.dy + math.sin(angle) * r2), paint..strokeWidth = 3); } canvas.drawCircle(center, radius * .42, Paint()..color = color.withOpacity(.12)); return; }
    if (type == 'waveform' || type == 'wave') { final path = Path(); for (var i = 0; i < values.length; i++) { final x = i / (values.length - 1) * size.width; final y = center.dy + math.sin(i * .55 + phase + position * 2) * values[i] * size.height * .30; if (i == 0) path.moveTo(x, y); else path.lineTo(x, y); } canvas.drawPath(path, paint..style = PaintingStyle.stroke..strokeWidth = 2.5); if (mirror) { canvas.save(); canvas.translate(0, size.height); canvas.scale(1, -1); canvas.drawPath(path, paint..color = color.withOpacity(.25)); canvas.restore(); } return; }
    final width = size.width / values.length; for (var i = 0; i < values.length; i++) { final h = values[i] * size.height * .78; final x = i * width + width / 2; canvas.drawLine(Offset(x, size.height * .92), Offset(x, size.height * .92 - h), paint..strokeWidth = math.max(2, width * .65)); }
  }
  @override bool shouldRepaint(covariant _VisualizationPainter old) => true;
}
