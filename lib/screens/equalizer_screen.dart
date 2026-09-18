import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/equalizer_provider.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  String _category = 'Genre';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          IconButton(
            tooltip: 'Save preset',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => _saveCustom(context),
          ),
          IconButton(
            tooltip: 'Reset flat',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => context.read<EqualizerProvider>().resetToFlat(),
          ),
        ],
      ),
      body: Consumer<EqualizerProvider>(
        builder: (context, eq, _) {
          final categories = eq.categories;
          if (categories.isNotEmpty && !categories.contains(_category)) {
            _category = categories.first;
          }
          final presets = eq.presetsInCategory(_category);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // Header status
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('Equalizer', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    eq.hasHardwareEq
                        ? '10-band studio curve → ${eq.hardwareBandCount} hardware bands'
                        : '10-band studio curve (hardware EQ not attached yet)',
                  ),
                  value: eq.isEnabled,
                  onChanged: eq.setEnabled,
                ),
              ),
              const SizedBox(height: 16),

              // Response curve
              Text('Frequency response', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: CustomPaint(
                      painter: _ResponseCurvePainter(
                        points: eq.responseCurvePoints(),
                        minDb: EqualizerProvider.studioMinDb,
                        maxDb: EqualizerProvider.studioMaxDb,
                        color: scheme.primary,
                        gridColor: scheme.outlineVariant.withValues(alpha: 0.45),
                        enabled: eq.isEnabled,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('31 Hz', style: Theme.of(context).textTheme.labelSmall),
                  Text('1 kHz', style: Theme.of(context).textTheme.labelSmall),
                  Text('16 kHz', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 18),

              // Preamp
              Text('Preamp', style: Theme.of(context).textTheme.titleMedium),
              // Symmetric -6..+6 so 0 dB sits at the visual center of the track.
              Slider(
                value: eq.preamp.clamp(-6.0, 6.0),
                min: -6,
                max: 6,
                divisions: 24,
                label: '${eq.preamp >= 0 ? '+' : ''}${eq.preamp.toStringAsFixed(1)} dB',
                onChanged: eq.isEnabled ? eq.setPreamp : null,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('-6 dB'),
                  Text('0'),
                  Text('+6 dB'),
                ],
              ),
              Text(
                'Zero is centered. On Android, preamp is applied softly so the '
                'device does not mute or clip; large moves still stay safe.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),

              // Preset categories
              Text('Presets', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in presets)
                    FilterChip(
                      label: Text(p.name),
                      selected: eq.preset == p.name,
                      onSelected: eq.isEnabled ? (_) => eq.applyPreset(p.name) : null,
                      onDeleted: p.isCustom ? () => eq.deleteCustomPreset(p.name) : null,
                      deleteIcon: p.isCustom ? const Icon(Icons.close, size: 16) : null,
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // 10 studio band sliders
              Text('Studio bands', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Always 10 bands. On Android they are mapped onto this device’s DSP '
                '(${eq.hasHardwareEq ? eq.hardwareBandCount : 0} hardware bands).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 260,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final band in eq.studioBands)
                      Expanded(
                        child: _StudioBandSlider(
                          band: band,
                          enabled: eq.isEnabled,
                          onChanged: (v) => eq.setStudioBandGain(band.index, v),
                        ),
                      ),
                  ],
                ),
              ),
              if (eq.preset == 'Custom')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Custom curve · use the bookmark icon to save',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveCustom(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'My mix',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await context.read<EqualizerProvider>().saveCustomPreset(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved “${name.trim()}”')),
    );
  }
}

class _StudioBandSlider extends StatelessWidget {
  final StudioBand band;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _StudioBandSlider({
    required this.band,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Column(
      children: [
        Text(
          '${band.gainDb >= 0 ? '+' : ''}${band.gainDb.toStringAsFixed(0)}',
          style: style,
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: band.gainDb.clamp(
                EqualizerProvider.studioMinDb,
                EqualizerProvider.studioMaxDb,
              ),
              min: EqualizerProvider.studioMinDb,
              max: EqualizerProvider.studioMaxDb,
              divisions: 48,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
        Text(
          _shortFreq(band.frequencyHz),
          textAlign: TextAlign.center,
          style: style,
        ),
      ],
    );
  }

  static String _shortFreq(double hz) {
    if (hz >= 1000) {
      final k = hz / 1000;
      return k >= 10 ? '${k.toStringAsFixed(0)}k' : '${k.toStringAsFixed(1)}k';
    }
    return '${hz.round()}';
  }
}

class _ResponseCurvePainter extends CustomPainter {
  final List<Offset> points; // x 0–1, y = dB
  final double minDb;
  final double maxDb;
  final Color color;
  final Color gridColor;
  final bool enabled;

  _ResponseCurvePainter({
    required this.points,
    required this.minDb,
    required this.maxDb,
    required this.color,
    required this.gridColor,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final zeroY = size.height * (1 - (0 - minDb) / (maxDb - minDb));

    // Grid
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), gridPaint);
    for (final frac in [0.25, 0.5, 0.75]) {
      final x = size.width * frac;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (points.length < 2) return;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = p.dx * size.width;
      final y = size.height * (1 - ((p.dy - minDb) / (maxDb - minDb)).clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = enabled ? color : color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Soft fill under curve
    final fillPath = Path.from(path)
      ..lineTo(size.width, zeroY)
      ..lineTo(0, zeroY)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (enabled ? color : color.withValues(alpha: 0.35)).withValues(alpha: 0.28),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ResponseCurvePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.enabled != enabled ||
        oldDelegate.color != color;
  }
}
