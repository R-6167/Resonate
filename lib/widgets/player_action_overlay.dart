import 'dart:ui';
import 'package:flutter/material.dart';

class PlayerActionOverlay {
  static Future<T?> show<T>({required BuildContext context, required Widget child, IconData? icon, String? title}) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withOpacity(.42),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => child,
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(opacity: curved, child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10 * animation.value, sigmaY: 10 * animation.value),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, .18), end: Offset.zero).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: .92, end: 1).animate(curved),
              child: SafeArea(child: Center(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680), child: _PanelSurface(icon: icon, title: title, child: child)),
              ))),
            ),
          ),
        ));
      },
    );
  }
}

class _PanelSurface extends StatelessWidget {
  final IconData? icon; final String? title; final Widget child;
  const _PanelSurface({this.icon, this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withOpacity(.96), elevation: 18, shadowColor: Colors.black.withOpacity(.45),
      clipBehavior: Clip.antiAlias, borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 38, height: 4, decoration: BoxDecoration(color: scheme.onSurfaceVariant.withOpacity(.45), borderRadius: BorderRadius.circular(8))),
          if (icon != null || title != null) ...[
            const SizedBox(height: 18),
            Row(children: [
              if (icon != null) Icon(icon, size: 25, color: scheme.primary),
              if (icon != null && title != null) const SizedBox(width: 12),
              if (title != null) Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
          ],
          Flexible(child: child),
        ]),
      ),
    );
  }
}
