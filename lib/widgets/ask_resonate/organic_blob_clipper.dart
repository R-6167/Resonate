import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft amoeba / organic blob silhouette.
class OrganicBlobClipper extends CustomClipper<Path> {
  final double progress;
  final double breathe;
  final double audioEnergy;

  const OrganicBlobClipper({
    required this.progress,
    this.breathe = 0,
    this.audioEnergy = 0,
  });

  @override
  Path getClip(Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.001) return Path();

    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.52;
    final energy = audioEnergy.clamp(0.0, 1.0);
    final rx = w * (0.18 + 0.30 * p + 0.04 * energy * p);
    final ry = h * (0.16 + 0.28 * p + 0.03 * energy * p);
    final wave = math.sin(breathe * math.pi * 2);
    final wave2 = math.cos(breathe * math.pi * 2 + 0.7);
    final amp = 10 + energy * 18;
    final o1 = wave * amp * p;
    final o2 = wave2 * (8 + energy * 12) * p;
    final o3 = wave * (6 + energy * 10) * p;
    final path = Path();
    path.moveTo(cx, cy - ry);
    path.cubicTo(cx + rx * 0.55 + o1, cy - ry * 0.95, cx + rx * 1.05 + o2, cy - ry * 0.25, cx + rx * 0.98, cy + ry * 0.15);
    path.cubicTo(cx + rx * 0.95 - o3, cy + ry * 0.55, cx + rx * 0.45, cy + ry * 1.05 + o1, cx, cy + ry * 0.98);
    path.cubicTo(cx - rx * 0.40, cy + ry * 1.02 - o2, cx - rx * 0.95 + o3, cy + ry * 0.50, cx - rx * 0.98, cy + ry * 0.08);
    path.cubicTo(cx - rx * 1.02 - o1, cy - ry * 0.30, cx - rx * 0.50, cy - ry * 0.92 + o2, cx, cy - ry);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant OrganicBlobClipper old) =>
      old.progress != progress || old.breathe != breathe || old.audioEnergy != audioEnergy;
}
