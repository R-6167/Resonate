import 'package:flutter/material.dart';

import '../modes/models/resonate_mode.dart';

/// Lightweight drawn identity for mode pickers and shelves.
/// User-supplied mode photographs are intentionally reserved for Now Playing.
class ModeArtworkBanner extends StatelessWidget {
  const ModeArtworkBanner({super.key, required this.mode});

  final ResonateMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(mode);
    final title = mode.label;
    final description = _description(mode);

    return Semantics(
      image: true,
      label: '$title mode artwork. $description',
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 172),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned(
                right: -28,
                top: -48,
                child: Container(
                  width: 176,
                  height: 176,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .16),
                      width: 24,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 18,
                bottom: -42,
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .08),
                  ),
                ),
              ),
              Positioned(
                right: 42,
                top: 18,
                child: Icon(
                  _icon(mode),
                  size: 64,
                  color: Colors.white.withValues(alpha: .13),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: SizedBox(
                  width: constraints.maxWidth - 36,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: .86),
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w800,
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
                          shadows: const [
                            Shadow(color: Colors.black45, blurRadius: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _asset(ResonateMode mode) => switch (mode) {
        ResonateMode.normal => 'assets/Normal_Mode.jpg',
        ResonateMode.running => 'assets/Running_Mode.jpg',
        ResonateMode.workout => 'assets/Workout_Mode.jpg',
        ResonateMode.driving => 'assets/Driving_Mode.jpg',
        ResonateMode.work => 'assets/Work_Mode.jpg',
        ResonateMode.podcast => 'assets/Podcast_Mode.jpg',
        ResonateMode.motivation => 'assets/Motivation_Mode.jpg',
        ResonateMode.audiobook => 'assets/Audiobook_Mode.jpg',
        ResonateMode.sleep => 'assets/Sleep_Mode.jpg',
      };

  static Alignment _alignment(ResonateMode mode) => switch (mode) {
        ResonateMode.normal => const Alignment(0, 0),
        ResonateMode.running => const Alignment(0, 0),
        ResonateMode.workout => const Alignment(0, 0.12),
        ResonateMode.driving => const Alignment(0, 0),
        ResonateMode.work => const Alignment(0, 0),
        ResonateMode.podcast => const Alignment(0, 0),
        ResonateMode.motivation => const Alignment(0, 0),
        ResonateMode.audiobook => const Alignment(0, 0),
        ResonateMode.sleep => const Alignment(0, 0),
      };

  static IconData _icon(ResonateMode mode) => switch (mode) {
        ResonateMode.normal => Icons.graphic_eq_rounded,
        ResonateMode.running => Icons.directions_run_rounded,
        ResonateMode.workout => Icons.fitness_center_rounded,
        ResonateMode.driving => Icons.directions_car_filled_rounded,
        ResonateMode.work => Icons.center_focus_strong_rounded,
        ResonateMode.podcast => Icons.mic_rounded,
        ResonateMode.motivation => Icons.bolt_rounded,
        ResonateMode.audiobook => Icons.menu_book_rounded,
        ResonateMode.sleep => Icons.nights_stay_rounded,
      };

  static String _description(ResonateMode mode) => switch (mode) {
        ResonateMode.normal => 'Your library, your sound.',
        ResonateMode.running => 'Find your rhythm. Keep moving.',
        ResonateMode.workout => 'Build momentum, one track at a time.',
        ResonateMode.driving => 'A soundtrack for the road ahead.',
        ResonateMode.work => 'Stay in flow with fewer distractions.',
        ResonateMode.podcast => 'Make room for voices and ideas.',
        ResonateMode.motivation => 'Bring the energy when you need it.',
        ResonateMode.audiobook => 'Settle in and follow the story.',
        ResonateMode.sleep => 'Slow the pace and wind down.',
      };

  static List<Color> _colors(ResonateMode mode) => switch (mode) {
        ResonateMode.running || ResonateMode.workout =>
          const [Color(0xFFEF6C35), Color(0xFF9D2F54)],
        ResonateMode.driving => const [Color(0xFF276A9B), Color(0xFF253D70)],
        ResonateMode.work => const [Color(0xFF277C78), Color(0xFF234D68)],
        ResonateMode.podcast || ResonateMode.audiobook =>
          const [Color(0xFF7454A6), Color(0xFF3F477E)],
        ResonateMode.sleep => const [Color(0xFF303F83), Color(0xFF171D42)],
        ResonateMode.motivation => const [Color(0xFFD66B28), Color(0xFF8C3E45)],
        ResonateMode.normal => const [Color(0xFF347A95), Color(0xFF373C78)],
      };
}

/// Full-screen mode photography. This widget is used only by Now Playing.
class ModeArtworkBackground extends StatelessWidget {
  const ModeArtworkBackground({super.key, required this.mode});

  final ResonateMode mode;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final cacheWidth =
        (media.size.width * media.devicePixelRatio).round().clamp(360, 1440);

    return Semantics(
      image: true,
      label: '${mode.label} mode background',
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            ModeArtworkBanner._asset(mode),
            fit: BoxFit.cover,
            alignment: ModeArtworkBanner._alignment(mode),
            filterQuality: FilterQuality.low,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: ModeArtworkBanner._colors(mode),
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99000000),
                  Color(0x55000000),
                  Color(0x88000000),
                  Color(0xDD000000),
                ],
                stops: [0, .30, .70, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact mode identity for the player surface; preserves playback-control space.
class ModeArtworkBadge extends StatelessWidget {
  const ModeArtworkBadge({super.key, required this.mode});

  final ResonateMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = ModeArtworkBanner._colors(mode);
    return Semantics(
      label: mode.label + ' mode active',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ModeArtworkBanner._icon(mode), size: 18, color: Colors.white),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                mode.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
