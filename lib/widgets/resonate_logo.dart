import 'package:flutter/material.dart';

class ResonateLogo extends StatelessWidget {
  final double size;
  const ResonateLogo({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _ResonateLogoPainter(color: Theme.of(context).colorScheme.primary));
}

class _ResonateLogoPainter extends CustomPainter {
  final Color color;
  _ResonateLogoPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = size.width * .105..strokeCap = StrokeCap.round;
    final c = Offset(size.width * .49, size.height * .52);
    for (var i = 0; i < 3; i++) {
      final r = size.width * (.19 + i * .12);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -1.02, 2.05, false, p);
    }
    final dot = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * .49, size.height * .52), size.width * .065, dot);
  }
  @override bool shouldRepaint(covariant _ResonateLogoPainter oldDelegate) => oldDelegate.color != color;
}
