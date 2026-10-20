import 'dart:ui';

import 'package:flutter/material.dart';

import '../ui/resonate_glass.dart';

/// Bottom sheet with Resonate glass barrier + frosted panel.
Future<T?> showBlurredModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : scheme.surface)
                .withValues(alpha: isDark ? 0.10 : 0.88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.40),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDragHandle)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              // Soft brand tint behind sheet content
              Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    ResonateAccents.violet.withValues(alpha: 0.12),
                                    Colors.transparent,
                                    ResonateAccents.blue.withValues(alpha: 0.08),
                                  ]
                                : [
                                    ResonateAccents.blue.withValues(alpha: 0.07),
                                    Colors.transparent,
                                    ResonateAccents.pink.withValues(alpha: 0.05),
                                  ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  builder(ctx),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Dialog with blurred barrier (builder supplies the dialog body).
Future<T?> showBlurredDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, sec) => builder(ctx),
    transitionBuilder: (ctx, anim, sec, child) {
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 14 * anim.value,
          sigmaY: 14 * anim.value,
        ),
        child: FadeTransition(opacity: anim, child: child),
      );
    },
  );
}
