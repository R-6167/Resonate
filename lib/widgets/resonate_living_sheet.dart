import 'dart:ui';

import 'package:flutter/material.dart';

/// Soft living sheet for volume, overflow menus, library actions.
Future<T?> showResonateLivingSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? semanticLabel,
}) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: semanticLabel ?? 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 420),
    pageBuilder: (ctx, anim, sec) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, sec, child) {
      final curved = reduce
          ? const AlwaysStoppedAnimation(1.0)
          : CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
      final scheme = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final t = curved.value.clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: barrierDismissible ? () => Navigator.of(ctx).maybePop() : null,
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: (reduce ? 8 : 14) * t, sigmaY: (reduce ? 8 : 14) * t),
                  child: Container(color: Colors.black.withValues(alpha: 0.28 * t)),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 48),
                    child: Transform.scale(
                      scale: reduce ? 1.0 : (0.92 + 0.08 * t),
                      alignment: Alignment.bottomCenter,
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: double.infinity,
                          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
                          margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.96 : 0.98),
                                scheme.primaryContainer.withValues(alpha: isDark ? 0.72 : 0.55),
                                scheme.secondaryContainer.withValues(alpha: isDark ? 0.45 : 0.35),
                              ],
                            ),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.18 * t),
                                blurRadius: 36,
                                spreadRadius: 2,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                Flexible(child: builder(ctx)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
