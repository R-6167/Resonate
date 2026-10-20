import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../modes/providers/mode_provider.dart';
import '../ui/resonate_glass.dart';

/// Shown when Bluetooth/car context is detected and Driving mode is not active.
class DrivingSuggestionBanner extends StatelessWidget {
  const DrivingSuggestionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ModeProvider>(
      builder: (context, modes, _) {
        if (!modes.isReady || !modes.hasDrivingSuggestion) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ResonateGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.directions_car_rounded, color: scheme.tertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Car audio detected',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Switch to Driving mode for larger controls and safer automation. '
                  'Your library stays intact — only policy and the mode shelf change.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.tonal(
                      onPressed: () => modes.acceptDrivingSuggestion(),
                      child: const Text('Use Driving'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => modes.dismissDrivingSuggestion(),
                      child: const Text('Not now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
