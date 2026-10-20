import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../providers/intelligence_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AskResonateController>();
    final intelligence = context.watch<IntelligenceProvider>();
    final scheme = Theme.of(context).colorScheme;

    // Hide while overlay is open (overlay can use the same mark as close affordance).
    if (ctrl.isOpen) return const SizedBox.shrink();

    return Positioned(
      right: 18,
      bottom: 108,
      child: GestureDetector(
        onTap: () {
          _capturePosition();
          ctrl.open();
        },
        onLongPress: () {
          _capturePosition();
          // Long-press opens compact capsule shape as a quick-action variant.
          ctrl.open(shape: AskResonateShape.capsule);
        },
        child: Material(
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
              ),
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.06, 1.06),
              duration: 2200.ms,
              curve: Curves.easeInOut,
            )
            .then()
            .tint(
              color: scheme.secondary.withValues(alpha: 0.08),
              duration: 2200.ms,
            ),
      ),
    );
  }
}
