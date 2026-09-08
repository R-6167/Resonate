import 'package:flutter/material.dart';

class ResonateLogo extends StatelessWidget {
  final double size;
  const ResonateLogo({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
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
