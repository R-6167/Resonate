import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/crossfade_provider.dart';

class CrossfadeScreen extends StatelessWidget {
  const CrossfadeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crossfade'),
        actions: [
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: Consumer<CrossfadeProvider>(
        builder: (context, crossfade, _) {
          final enabled = crossfade.isEnabled;
          final durationMs = crossfade.duration.clamp(0.0, 12000.0);
          final fadeType = crossfade.fadeType;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Transition',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Blend the end of one track into the beginning of the next using dual engines (A → B).',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
                  secondary: const Icon(Icons.multitrack_audio_rounded),
                  title: const Text(
                    'Crossfade',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    enabled
                        ? 'Dual-engine transitions · ${crossfade.getDurationString()}'
                        : 'Tracks play end-to-end with a hard cut',
                  ),
                  value: enabled,
                  onChanged: crossfade.toggleCrossfade,
                ),
              ),

              if (enabled) ...[
                const SizedBox(height: 22),
                Text('Volume curve', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'Outgoing track fades down while the next track fades up over the duration.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: CustomPaint(
                        painter: _CrossfadeCurvePainter(
                          fadeType: fadeType,
                          outgoingColor: scheme.error,
                          incomingColor: scheme.primary,
                          gridColor: scheme.outlineVariant.withValues(alpha: 0.45),
                          labelColor: scheme.onSurfaceVariant,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _LegendDot(color: scheme.error, label: 'Outgoing'),
                    const SizedBox(width: 16),
                    _LegendDot(color: scheme.primary, label: 'Incoming'),
                    const Spacer(),
                    Text(
                      crossfade.getDurationString(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),

                const SizedBox(height: 22),
                Text('Duration', style: Theme.of(context).textTheme.titleMedium),
                Slider(
                  value: durationMs <= 0 ? 3000 : durationMs,
                  min: 500,
                  max: 12000,
                  divisions: 23,
                  label: crossfade.getDurationString(),
                  onChanged: (v) => crossfade.setDuration(v),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final ms in [1000.0, 2000.0, 3000.0, 5000.0, 8000.0, 12000.0])
                      ChoiceChip(
                        label: Text(_msLabel(ms)),
                        selected: (durationMs - ms).abs() < 50,
                        onSelected: (_) => crossfade.setDuration(ms),
                      ),
                  ],
                ),

                const SizedBox(height: 22),
                Text('Curve shape', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const [
                      ('linear', 'Linear'),
                      ('ease_in', 'Ease in'),
                      ('ease_out', 'Ease out'),
                      ('ease_in_out', 'Ease in–out'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: fadeType == entry.$1,
                        onSelected: (_) => crossfade.setFadeType(entry.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _curveDescription(fadeType),
                  style: Theme.of(context).textTheme.bodySmall,
                ),

                const SizedBox(height: 22),
                Card(
                  elevation: 0,
                  child: ListTile(
                    leading: Icon(Icons.sync_alt_rounded, color: scheme.primary),
                    title: const Text('How Resonate does it'),
                    subtitle: const Text(
                      'Engine B loads the next track at volume 0, then both engines '
                      'fade over the duration. After the hand-off, B becomes active '
                      'and A is stopped. User next/pause can cancel a transition.',
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _msLabel(double ms) {
    if (ms < 1000) return '${ms.round()}ms';
    final s = ms / 1000;
    return s == s.roundToDouble() ? '${s.toInt()}s' : '${s.toStringAsFixed(1)}s';
  }

  static String _curveDescription(String type) {
    return switch (type) {
      'ease_in' => 'Starts slow, then speeds up — incoming arrives more abruptly at the end.',
      'ease_out' => 'Starts fast, then settles — outgoing drops quickly at first.',
      'ease_in_out' => 'Smooth S-curve — gentle at both ends, faster in the middle.',
      _ => 'Constant rate — volume of each engine moves linearly with time.',
    };
  }

  Future<void> _confirmReset(BuildContext context) async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset crossfade?'),
        content: const Text(
          'Crossfade will be turned off and the fade curve will return to Linear.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (reset == true && context.mounted) {
      await context.read<CrossfadeProvider>().reset();
    }
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// Maps linear time 0–1 through the same easing used by the playback engine.
double _fadeT(String fadeType, double linear) {
  final x = linear.clamp(0.0, 1.0);
  return switch (fadeType) {
    'ease_in' => x * x,
    'ease_out' => 1.0 - ((1.0 - x) * (1.0 - x)),
    'ease_in_out' => x < 0.5
        ? 2.0 * x * x
        : 1.0 - math.pow(-2.0 * x + 2.0, 2).toDouble() / 2.0,
    _ => x,
  };
}

class _CrossfadeCurvePainter extends CustomPainter {
  final String fadeType;
  final Color outgoingColor;
  final Color incomingColor;
  final Color gridColor;
  final Color labelColor;

  _CrossfadeCurvePainter({
    required this.fadeType,
    required this.outgoingColor,
    required this.incomingColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Horizontal volume guides at 0 / 50 / 100%
    for (final frac in [0.0, 0.5, 1.0]) {
      final y = size.height * (1 - frac);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Mid time
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      grid,
    );

    const samples = 48;
    final outPath = Path();
    final inPath = Path();

    for (var i = 0; i < samples; i++) {
      final linear = i / (samples - 1);
      final t = _fadeT(fadeType, linear);
      final outVol = 1.0 - t;
      final inVol = t;
      final x = linear * size.width;
      final outY = size.height * (1 - outVol);
      final inY = size.height * (1 - inVol);
      if (i == 0) {
        outPath.moveTo(x, outY);
        inPath.moveTo(x, inY);
      } else {
        outPath.lineTo(x, outY);
        inPath.lineTo(x, inY);
      }
    }

    final outPaint = Paint()
      ..color = outgoingColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final inPaint = Paint()
      ..color = incomingColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(outPath, outPaint);
    canvas.drawPath(inPath, inPaint);

    // Cross point marker near mid when linear, or at equal volume
    for (var i = 0; i < samples; i++) {
      final linear = i / (samples - 1);
      final t = _fadeT(fadeType, linear);
      if ((t - 0.5).abs() < 0.02) {
        final x = linear * size.width;
        final y = size.height * 0.5;
        canvas.drawCircle(
          Offset(x, y),
          4,
          Paint()..color = incomingColor.withValues(alpha: 0.85),
        );
        break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CrossfadeCurvePainter oldDelegate) {
    return oldDelegate.fadeType != fadeType ||
        oldDelegate.outgoingColor != outgoingColor ||
        oldDelegate.incomingColor != incomingColor;
  }
}
