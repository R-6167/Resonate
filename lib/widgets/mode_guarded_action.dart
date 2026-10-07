import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../modes/models/mode_action.dart';
import '../modes/providers/mode_provider.dart';
import '../modes/services/mode_interaction_guard.dart';

/// Host UI gate: tracks simultaneous pointers and only fires [onAllowed] when
/// [ModeInteractionGuard] accepts the action (e.g. two-finger Running taps).
class ModeGuardedAction extends StatefulWidget {
  const ModeGuardedAction({
    super.key,
    required this.action,
    required this.onAllowed,
    required this.child,
    this.showBlockedFeedback = true,
  });

  final ModeAction action;
  final VoidCallback onAllowed;
  final Widget child;
  final bool showBlockedFeedback;

  @override
  State<ModeGuardedAction> createState() => _ModeGuardedActionState();
}

class _ModeGuardedActionState extends State<ModeGuardedAction> {
  final Set<int> _pointers = <int>{};
  DateTime? _downAt;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _pointers.add(e.pointer);
        _downAt ??= DateTime.now();
      },
      onPointerUp: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.isEmpty) _downAt = null;
      },
      onPointerCancel: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.isEmpty) _downAt = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tryAllow(context),
        child: widget.child,
      ),
    );
  }

  void _tryAllow(BuildContext context) {
    final modes = context.read<ModeProvider>();
    final guard = ModeInteractionGuard(modes.interactionPolicy);
    final duration = _downAt == null
        ? Duration.zero
        : DateTime.now().difference(_downAt!);
    // Use peak concurrent pointers during this gesture (count at tap includes
    // any still down). Clamp to at least 1 for a normal single tap.
    final count = _pointers.isEmpty ? 1 : _pointers.length;

    final allowed = guard.allowTap(
      action: widget.action,
      pointerCount: count,
      duration: duration,
    );
    if (allowed) {
      widget.onAllowed();
      return;
    }
    if (widget.showBlockedFeedback && context.mounted) {
      final needTwo = modes.interactionPolicy.requiresTwoFingerTap(widget.action);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            needTwo
                ? 'Running mode: use two fingers for ${widget.action.name}'
                : 'Action blocked by mode interaction policy',
          ),
          duration: const Duration(milliseconds: 1600),
        ),
      );
    }
  }
}
