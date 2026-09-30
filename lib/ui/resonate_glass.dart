import 'dart:ui';

import 'package:flutter/material.dart';

/// Brand accents matching the Equalizer glass UI (logo spectrum).
abstract final class ResonateAccents {
  static const blue = Color(0xFF5B8CFF);
  static const violet = Color(0xFF9B6DFF);
  static const pink = Color(0xFFFF6BB5);
  static const orange = Color(0xFFFF8A4C);
  static const night = Color(0xFF0E0B18);
  static const nightDeep = Color(0xFF0A0A12);
}

/// Soft brand wash behind content — same recipe as the Equalizer screen.
class ResonateGlassBackground extends StatelessWidget {
  const ResonateGlassBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      ResonateAccents.night,
                      ResonateAccents.violet.withValues(alpha: 0.18),
                      ResonateAccents.blue.withValues(alpha: 0.12),
                      ResonateAccents.nightDeep,
                    ]
                  : [
                      scheme.surface,
                      ResonateAccents.blue.withValues(alpha: 0.08),
                      ResonateAccents.pink.withValues(alpha: 0.06),
                      scheme.surface,
                    ],
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

/// Scaffold with transparent AppBar + glass gradient body.
class ResonateGlassScaffold extends StatelessWidget {
  const ResonateGlassScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.leading,
  });

  final Widget title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: leading,
        title: title,
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: ResonateGlassBackground(
        child: SafeArea(child: body),
      ),
    );
  }
}

/// Frosted glass card — Equalizer recipe (blur 18, soft border, light lift).
class ResonateGlassCard extends StatelessWidget {
  const ResonateGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.margin,
    this.borderRadius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: (isDark ? Colors.white : scheme.surface)
                .withValues(alpha: isDark ? 0.08 : 0.55),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (margin != null) {
      return Padding(padding: margin!, child: card);
    }
    return card;
  }
}

/// Expandable glass section used by Settings-style hubs.
class ResonateGlassSection extends StatelessWidget {
  const ResonateGlassSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
    this.accent,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return ResonateGlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          children: children,
        ),
      ),
    );
  }
}

/// Row tile inside a glass section / card.
class ResonateGlassTile extends StatelessWidget {
  const ResonateGlassTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.onTap,
    this.trailing,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.onSurface.withValues(alpha: 0.75);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: color),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          )),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
            ),
      trailing: trailing ??
          (onTap == null
              ? null
              : Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.35),
                )),
      onTap: onTap,
    );
  }
}
