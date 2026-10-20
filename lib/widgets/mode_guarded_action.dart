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
  int _peakPointers = 0;
  DateTime? _downAt;

  void _onDown(PointerDownEvent e) {
    if (_pointers.isEmpty) {
      _peakPointers = 0;
      _downAt = DateTime.now();
    }
    _pointers.add(e.pointer);
    if (_pointers.length > _peakPointers) {
      _peakPointers = _pointers.length;
    }
  }

  void _onUp(int pointer) {
    _pointers.remove(pointer);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerUp: (e) => _onUp(e.pointer),
      onPointerCancel: (e) => _onUp(e.pointer),
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
    // Peak concurrent pointers during the gesture (onTap often fires after
    // the last pointer is already up).
    final count = _peakPointers <= 0 ? 1 : _peakPointers;

    final allowed = guard.allowTap(
      action: widget.action,
      pointerCount: count,
      duration: duration,
    );

    _peakPointers = 0;
    _downAt = null;
    _pointers.clear();

    if (allowed) {
      widget.onAllowed();
      return;
    }
    if (widget.showBlockedFeedback && context.mounted) {
      final needTwo =
          modes.interactionPolicy.requiresTwoFingerTap(widget.action);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            needTwo
                ? 'Running mode: use two fingers for transport'
                : 'Action blocked by mode interaction policy',
          ),
          duration: const Duration(milliseconds: 1600),
        ),
      );
    }
  }
}
