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

  void _openWithShape(AskResonateShape shape) {
    _capturePosition();
    context.read<AskResonateController>().open(shape: shape);
  }

  void _showShapeMenu() {
    _capturePosition();
    final ctrl = context.read<AskResonateController>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.bubble_chart),
                title: const Text('Organic blob'),
                onTap: () {
                  Navigator.pop(ctx);
                  ctrl.open(shape: AskResonateShape.blob);
                },
              ),
              ListTile(
                leading: const Icon(Icons.smart_button),
                title: const Text('Capsule'),
                onTap: () {
                  Navigator.pop(ctx);
                  ctrl.open(shape: AskResonateShape.capsule);
                },
              ),
              ListTile(
                leading: const Icon(Icons.vertical_split),
                title: const Text('Edge semicircle'),
                onTap: () {
                  Navigator.pop(ctx);
                  ctrl.open(shape: AskResonateShape.semicircle);
                },
              ),
              ListTile(
                leading: const Icon(Icons.radio_button_checked),
                title: const Text('Orbital'),
                onTap: () {
                  Navigator.pop(ctx);
                  ctrl.open(shape: AskResonateShape.orbital);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AskResonateController>();
    final intelligence = context.watch<IntelligenceProvider>();
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Hide while overlay is open.
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
          ),
        ),
      ),
    );

    if (!reduceMotion) {
      orb = orb
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
          );
    }

    return Positioned(
      right: 18,
      bottom: 108,
      child: Semantics(
        button: true,
        label: 'Ask Resonate',
        hint: 'Opens the Resonate companion. Long press to choose overlay shape.',
        child: GestureDetector(
          onTap: () => _openWithShape(AskResonateShape.blob),
          onLongPress: _showShapeMenu,
          child: orb,
        ),
      ),
    );
  }
}
