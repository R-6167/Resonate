#!/usr/bin/env python3
"""Step 6: glass sheets/dialogs + AutopilotHomeCard + EvolvingMixCard."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def polish_blur_sheet() -> None:
    path = ROOT / "lib/widgets/blur_sheet.dart"
    # Full rewrite to EQ-aligned glass recipe
    path.write_text(
        '''import 'dart:ui';

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
              // Soft brand wash under sheet content
              Flexible(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isDark
                                  ? [
                                      ResonateAccents.violet.withValues(alpha: 0.10),
                                      Colors.transparent,
                                      ResonateAccents.blue.withValues(alpha: 0.06),
                                    ]
                                  : [
                                      ResonateAccents.blue.withValues(alpha: 0.06),
                                      Colors.transparent,
                                      ResonateAccents.pink.withValues(alpha: 0.04),
                                    ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    builder(ctx),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Dialog with blurred barrier + optional glass frame via [builder].
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
'''
    )
    print("blur_sheet rewritten")


def polish_autopilot() -> None:
    path = ROOT / "lib/widgets/autopilot_home_card.dart"
    t = path.read_text()
    if "resonate_glass.dart" not in t:
        t = t.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
            1,
        )
    old = '''    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.95),
            scheme.surfaceContainerHighest.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
'''
    new = '''    return ResonateGlassCard(
      borderRadius: 24,
      padding: EdgeInsets.zero,
      child: Column(
'''
    if old not in t:
        if "ResonateGlassCard" in t:
            print("autopilot already glass")
            return
        raise SystemExit("autopilot outer container not found")
    t = t.replace(old, new, 1)
    path.write_text(t)
    print("autopilot → glass")


def polish_evolving() -> None:
    path = ROOT / "lib/widgets/evolving_mix_card.dart"
    t = path.read_text()
    if "resonate_glass.dart" not in t:
        t = t.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
            1,
        )

    old_gen = '''    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        gradient: LinearGradient(
          colors: [
            scheme.tertiaryContainer.withValues(alpha: 0.35),
            scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
'''
    new_gen = '''    return ResonateGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
'''
    if old_gen in t:
        t = t.replace(old_gen, new_gen, 1)
        print("generate card → glass")
    elif "ResonateGlassCard" in t and "_GenerateCard" in t:
        print("generate card already glass-ish")
    else:
        raise SystemExit("generate card pattern not found")

    old_j = '''    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
'''
    new_j = '''    return ResonateGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
'''
    if old_j in t:
        t = t.replace(old_j, new_j, 1)
        # Journey had an extra Padding wrapper — remove one closing if needed.
        # Structure was Container > Padding > Column. Now Glass > Column.
        # Need to remove one matching close of Padding — find after replacement.
        # Safer: leave Padding by using padding on glass (done) and remove inner Padding widget's close paren.
        # After replace, we have:
        # return ResonateGlassCard(... child: Column(
        #   ...
        #   ),  // column
        # ),    // was padding
        # );    // was container
        # Original end: child: Padding( ... child: Column( ... ), ), );
        # We need Column close + glass close only.
        # Search for journey card method end pattern - risky.
        # Instead keep Padding inside:
        t = t.replace(new_j, '''    return ResonateGlassCard(
      borderRadius: 20,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
''', 1)
        print("journey card → glass")
    else:
        raise SystemExit("journey card pattern not found")

    path.write_text(t)
    print("evolving polished")


def main() -> None:
    polish_blur_sheet()
    polish_autopilot()
    polish_evolving()
    print("step 6 done")


if __name__ == "__main__":
    main()
