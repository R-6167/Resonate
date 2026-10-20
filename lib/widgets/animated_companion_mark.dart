import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnimatedCompanionMark extends StatefulWidget {
  final String mode;
  final double size;
  const AnimatedCompanionMark({super.key, required this.mode, this.size = 28});
  @override State<AnimatedCompanionMark> createState() => _AnimatedCompanionMarkState();
}

class _AnimatedCompanionMarkState extends State<AnimatedCompanionMark> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  @override void dispose() { _controller.dispose(); super.dispose(); }
  IconData get _icon => switch (widget.mode) { 'Suggest' => Icons.lightbulb_rounded, 'Assist me' || 'Assist' => Icons.auto_awesome_rounded, 'Autopilot' => Icons.smart_toy_rounded, _ => Icons.auto_awesome_rounded };
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _controller, builder: (_, child) { final wave = math.sin(_controller.value * math.pi * 2); final scale = 1 + wave * .07; final turns = widget.mode == 'Autopilot' ? wave * .018 : wave * .008; return Transform.rotate(angle: turns, child: Transform.scale(scale: scale, child: child)); }, child: Icon(_icon, size: widget.size));
}
