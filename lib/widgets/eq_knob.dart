import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rotary knob for EQ / preamp style controls.
class EqKnob extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String label;
  final String? unit;
  final bool enabled;
  final ValueChanged<double>? onChanged;
  final double size;

  const EqKnob({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    this.unit,
    this.enabled = true,
    this.onChanged,
    this.size = 72,
  });

  @override
  State<EqKnob> createState() => _EqKnobState();
}

class _EqKnobState extends State<EqKnob> {
  double? _dragStartValue;
  double? _dragStartY;

  double get _t =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final display = widget.value >= 0 && widget.min < 0
        ? '+${widget.value.toStringAsFixed(1)}'
        : widget.value.toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onVerticalDragStart: widget.enabled && widget.onChanged != null
              ? (d) {
                  _dragStartValue = widget.value;
                  _dragStartY = d.localPosition.dy;
                }
              : null,
          onVerticalDragUpdate: widget.enabled && widget.onChanged != null
              ? (d) {
                  if (_dragStartValue == null || _dragStartY == null) return;
                  final dy = _dragStartY! - d.localPosition.dy;
                  final range = widget.max - widget.min;
                  final delta = (dy / 100) * range;
                  final next =
                      (_dragStartValue! + delta).clamp(widget.min, widget.max);
                  widget.onChanged!(next);
                }
              : null,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _KnobPainter(
              t: _t,
              enabled: widget.enabled,
              track: scheme.outlineVariant,
              active: scheme.primary,
              face: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$display${widget.unit ?? ''}',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: widget.enabled
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: 0.4),
              ),
        ),
        Text(
          widget.label,
          style: Theme.of(context).textTheme.labelSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double t;
  final bool enabled;
  final Color track;
  final Color active;
  final Color face;

  _KnobPainter({
    required this.t,
    required this.enabled,
    required this.track,
    required this.active,
    required this.face,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;

    // Track arc (270°)
    final trackPaint = Paint()
      ..color = track.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const start = -math.pi * 0.75;
    const sweep = math.pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      trackPaint,
    );

    final activePaint = Paint()
      ..color = enabled ? active : active.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep * t,
      false,
      activePaint,
    );

    // Face
    canvas.drawCircle(
      c,
      r - 10,
      Paint()..color = face,
    );

    // Pointer
    final angle = start + sweep * t;
    final p1 = Offset(
      c.dx + math.cos(angle) * (r - 22),
      c.dy + math.sin(angle) * (r - 22),
    );
    final p2 = Offset(
      c.dx + math.cos(angle) * (r - 12),
      c.dy + math.sin(angle) * (r - 12),
    );
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = enabled ? active : track
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _KnobPainter old) =>
      old.t != t || old.enabled != enabled;
}
