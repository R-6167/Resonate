import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/intelligence_provider.dart';
import '../../providers/audio_visualization_provider.dart';
import '../animated_companion_mark.dart';
import 'ask_resonate_controller.dart';

/// Persistent floating entry for Ask Resonate.
///
/// Place once in the shell [Stack] so it survives tab switches.
class AskResonateOrb extends StatefulWidget {
  const AskResonateOrb({super.key});

  @override
  State<AskResonateOrb> createState() => _AskResonateOrbState();
}

class _AskResonateOrbState extends State<AskResonateOrb> {
  final GlobalKey _orbKey = GlobalKey();

  void _capturePosition() {
    final box = _orbKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final pos = box.localToGlobal(Offset.zero) +
        Offset(box.size.width / 2, box.size.height / 2);
    context.read<AskResonateController>().updateOrbGlobalPosition(pos);
  }

  void _open() {
    _capturePosition();
    context.read<AskResonateController>().open();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AskResonateController>();
    final intelligence = context.watch<IntelligenceProvider>();
    final viz = context.watch<AudioVisualizationProvider>();
    final lowBandEnergy =
        viz.enabled && viz.orbAudioReactive && viz.frequencies.isNotEmpty
            ? math
                .sqrt(viz.frequencies.take(6).fold<double>(0, (sum, value) => sum + value) / 6)
                .clamp(0.0, 1.0)
                .toDouble()
            : 0.0;
    final audioScale =
        1.0 + (lowBandEnergy * viz.sensitivity * 0.28).clamp(0.0, 0.28).toDouble();
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (ctrl.isOpen) return const SizedBox.shrink();

    Widget orb = Material(
      key: _orbKey,
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.secondary.withValues(alpha: 0.95),
              scheme.primary.withValues(alpha: 0.90),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: AnimatedCompanionMark(
            mode: intelligence.autonomyLabel,
            size: 28,
            audioEnergy: reduceMotion ? 0.0 : lowBandEnergy * viz.sensitivity,
          ),
        ),
      ),
    );

    orb = Transform.scale(scale: reduceMotion ? 1.0 : audioScale, child: orb);

    return Positioned(
      right: 18,
      bottom: 16,
      child: Semantics(
        button: true,
        label: 'Ask Resonate',
        hint: 'Opens the Resonate companion.',
        onTap: _open,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: orb,
        ),
      ),
    );
  }
}
