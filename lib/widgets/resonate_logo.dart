import 'package:flutter/material.dart';

/// Brand mark: app-icon mark beside the Resonate wordmark (Home AppBar).
/// Use [full] for the complete in-app logo square (About).
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

  static const _inApp = 'assets/branding/resonate_in_app_logo.png';
  static const _mark = 'assets/branding/resonate_app_icon.png';

  @override
  Widget build(BuildContext context) {
    if (full) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: Image.asset(
          _inApp,
          height: size,
          width: size,
          fit: BoxFit.cover,
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
            _mark,
            height: markSize,
            width: markSize,
            fit: BoxFit.cover,
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
