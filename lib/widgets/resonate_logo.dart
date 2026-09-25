import 'package:flutter/material.dart';

/// In-app brand: [resonate_in_app_logo] mark beside the Resonate wordmark.
/// Use [full] for the larger square mark (About hero).
class ResonateLogo extends StatelessWidget {
  final double size;
  final bool full;
  final bool showWord;

  const ResonateLogo({
    super.key,
    this.size = 34,
    this.full = false,
    this.showWord = true,
  });

  /// Full brand art for in-app surfaces (Home, About).
  static const _inApp = 'assets/branding/resonate_in_app_logo.png';

  @override
  Widget build(BuildContext context) {
    if (full) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: Image.asset(
          _inApp,
          height: size,
          width: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _textOnly(context, size),
        ),
      );
    }

    final markSize = size;
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: size * .55,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          letterSpacing: -1.2,
          height: .95,
          color: Theme.of(context).colorScheme.primary,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(markSize * 0.22),
          child: Image.asset(
            _inApp,
            height: markSize,
            width: markSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Icon(
              Icons.graphic_eq_rounded,
              size: markSize * 0.85,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        if (showWord) ...[
          SizedBox(width: size * 0.22),
          Text('Resonate', style: style),
        ],
      ],
    );
  }

  Widget _textOnly(BuildContext context, double size) {
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: size * .72,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          letterSpacing: -1.4,
          height: .95,
          color: Theme.of(context).colorScheme.primary,
        );
    return Text('Resonate', style: style);
  }
}
