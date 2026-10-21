import 'package:flutter/material.dart';

import '../modes/models/resonate_mode.dart';

/// Lightweight, local-only illustration for a listening mode.
/// Uses Material icons and gradients instead of large image assets.
class ModeArtworkBanner extends StatelessWidget {
  const ModeArtworkBanner({super.key, required this.mode});

  final ResonateMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(mode);
    final icon = _icon(mode);
    final description = _description(mode);
    final title = mode.label;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      image: true,
      label: '$title mode artwork. $description',
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 148),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -42,
              child: Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: .14), width: 24),
                ),
              ),
            ),
            Positioned(
              right: 28,
              bottom: -56,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white.withValues(alpha: .78),
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            height: 1.18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withValues(alpha: .2)),
                    ),
                    child: Icon(icon, size: 52, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(ResonateMode mode) {
    final value = mode.name.toLowerCase();
    if (value.contains('run')) return Icons.directions_run_rounded;
    if (value.contains('workout')) return Icons.fitness_center_rounded;
    if (value.contains('driv')) return Icons.directions_car_filled_rounded;
    if (value.contains('work')) return Icons.center_focus_strong_rounded;
    if (value.contains('podcast')) return Icons.mic_rounded;
    if (value.contains('audio') || value.contains('book')) return Icons.menu_book_rounded;
    if (value.contains('sleep')) return Icons.nights_stay_rounded;
    if (value.contains('motivat')) return Icons.bolt_rounded;
    return Icons.graphic_eq_rounded;
  }

  static String _description(ResonateMode mode) {
    final value = mode.name.toLowerCase();
    if (value.contains('run')) return 'Find your rhythm. Keep moving.';
    if (value.contains('workout')) return 'Build momentum, one track at a time.';
    if (value.contains('driv')) return 'A soundtrack for the road ahead.';
    if (value.contains('work')) return 'Stay in flow with fewer distractions.';
    if (value.contains('podcast')) return 'Make room for voices and ideas.';
    if (value.contains('audio') || value.contains('book')) return 'Settle in and follow the story.';
    if (value.contains('sleep')) return 'Slow the pace and wind down.';
    if (value.contains('motivat')) return 'Bring the energy when you need it.';
    return 'Your library, your sound.';
  }

  static List<Color> _colors(ResonateMode mode) {
    final value = mode.name.toLowerCase();
    if (value.contains('run') || value.contains('workout')) {
      return const [Color(0xFFEF6C35), Color(0xFF9D2F54)];
    }
    if (value.contains('driv')) return const [Color(0xFF276A9B), Color(0xFF253D70)];
    if (value.contains('work')) return const [Color(0xFF277C78), Color(0xFF234D68)];
    if (value.contains('podcast') || value.contains('audio') || value.contains('book')) {
      return const [Color(0xFF7454A6), Color(0xFF3F477E)];
    }
    if (value.contains('sleep')) return const [Color(0xFF303F83), Color(0xFF171D42)];
    if (value.contains('motivat')) return const [Color(0xFFD66B28), Color(0xFF8C3E45)];
    return const [Color(0xFF347A95), Color(0xFF373C78)];
  }
}
