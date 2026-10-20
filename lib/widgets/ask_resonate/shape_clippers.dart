import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ask_resonate_controller.dart';
import 'organic_blob_clipper.dart';

/// Dispatches to the correct [CustomClipper] for [AskResonateShape].
CustomClipper<Path> clipperForShape({
  required AskResonateShape shape,
  required double progress,
  double breathe = 0,
  double audioEnergy = 0,
}) {
  switch (shape) {
    case AskResonateShape.blob:
      return OrganicBlobClipper(
        progress: progress,
        breathe: breathe,
        audioEnergy: audioEnergy,
      );
    case AskResonateShape.semicircle:
      return SemicircleClipper(
        progress: progress,
        breathe: breathe,
        audioEnergy: audioEnergy,
      );
    case AskResonateShape.capsule:
      return CapsuleClipper(
        progress: progress,
        breathe: breathe,
        audioEnergy: audioEnergy,
      );
    case AskResonateShape.orbital:
      return OrbitalClipper(
        progress: progress,
        breathe: breathe,
        audioEnergy: audioEnergy,
      );
  }
}

/// Right-edge semicircle dock.
class SemicircleClipper extends CustomClipper<Path> {
  final double progress;
  final double breathe;
  final double audioEnergy;

  const SemicircleClipper({
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
    final energy = (audioEnergy * 0.04).clamp(0.0, 0.06);
    final radius = (math.min(w, h) * 0.48 + energy * w) * p;
    final cx = w; // docked to right edge
    final cy = h * 0.5;
    final wobble = math.sin(breathe * math.pi * 2) * 6 * p;

    final path = Path();
    path.moveTo(cx, cy - radius);
    path.arcToPoint(
      Offset(cx, cy + radius),
      radius: Radius.circular(radius + wobble),
      clockwise: false,
    );
    path.lineTo(cx, cy - radius);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant SemicircleClipper old) =>
      old.progress != progress ||
      old.breathe != breathe ||
      old.audioEnergy != audioEnergy;
}

/// Rounded horizontal capsule / pill.
class CapsuleClipper extends CustomClipper<Path> {
  final double progress;
  final double breathe;
  final double audioEnergy;

  const CapsuleClipper({
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
    final energy = audioEnergy.clamp(0.0, 1.0);
    final insetX = w * (0.08 - 0.02 * energy) * (1 - p);
    final insetY = h * (0.22 - 0.04 * energy) * (1 - p);
    final breatheY = math.sin(breathe * math.pi * 2) * 4 * p;

    final rect = RRect.fromLTRBR(
      insetX,
      insetY + breatheY,
      w - insetX,
      h - insetY + breatheY,
      Radius.circular(h * 0.22 * p + 12),
    );
    return Path()..addRRect(rect);
  }

  @override
  bool shouldReclip(covariant CapsuleClipper old) =>
      old.progress != progress ||
      old.breathe != breathe ||
      old.audioEnergy != audioEnergy;
}

/// Soft circular orbital panel (center-weighted).
class OrbitalClipper extends CustomClipper<Path> {
  final double progress;
  final double breathe;
  final double audioEnergy;

  const OrbitalClipper({
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
    final cy = h * 0.5;
    final energy = audioEnergy.clamp(0.0, 1.0);
    final base = math.min(w, h) * (0.22 + 0.28 * p);
    final pulse = math.sin(breathe * math.pi * 2) * 8 * p +
        energy * 14 * p;

    return Path()
      ..addOval(
        Rect.fromCircle(center: Offset(cx, cy), radius: base + pulse),
      );
  }

  @override
  bool shouldReclip(covariant OrbitalClipper old) =>
      old.progress != progress ||
      old.breathe != breathe ||
      old.audioEnergy != audioEnergy;
}
