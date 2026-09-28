import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/bluetooth_provider.dart';
import '../providers/equalizer_provider.dart';
import '../services/dsp_engine_bridge.dart';
import '../widgets/eq_knob.dart';

/// Equalizer screen redesigned around openable sections so the main view
/// stays simple while advanced options stay one tap away.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  String _category = 'Genre';
  bool _categorySynced = false;
  final Set<String> _open = {'power', 'curve', 'bands'};

  @override
  void initState() {
    super.initState();
    DspEngineBridge.instance.ensureInitialized().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _syncCategoryFromPreset(EqualizerProvider eq) {
    if (_categorySynced) return;
    for (final p in eq.allPresets) {
      if (p.name == eq.preset) {
        _category = p.category;
        _categorySynced = true;
        return;
      }
    }
    _categorySynced = true;
  }

  bool _isOpen(String id) => _open.contains(id);

  void _toggle(String id) {
    setState(() {
      if (_open.contains(id)) {
        _open.remove(id);
      } else {
        _open.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dsp = DspEngineBridge.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          IconButton(
            tooltip: 'How to use',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => _showHelp(context),
          ),
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
          _syncCategoryFromPreset(eq);
          final categories = eq.categories;
          if (categories.isNotEmpty && !categories.contains(_category)) {
            _category = categories.first;
          }
          final presets = eq.presetsInCategory(_category);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
            children: [
              // ── Power ─────────────────────────────────────────────
              _Section(
                id: 'power',
                title: 'Power & engine',
                subtitle: eq.isEnabled ? 'EQ on' : 'EQ off',
                icon: Icons.power_settings_new_rounded,
                open: _isOpen('power'),
                onToggle: () => _toggle('power'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable equalizer'),
                      subtitle: Text(
                        eq.hasHardwareEq
                            ? '${eq.hardwareBandCount} hardware bands · studio model active'
                            : 'Hardware EQ attaches after playback starts',
                      ),
                      value: eq.isEnabled,
                      onChanged: eq.setEnabled,
                    ),
                    const SizedBox(height: 8),
                    _Hint(
                      'Tip: Turn EQ on, pick a preset under Presets, then fine-tune '
                      'bands only if you need to. Flat = no change to the recording.',
                    ),
                    const SizedBox(height: 12),
                    _EngineCard(
                      dspAvailable: dsp.isAvailable,
                      dspVersion: dsp.version,
                      dspId: DspEngineBridge.engineId,
                      studioId: eq.dspEngineId,
                      nativeActive: eq.nativeDspActive,
                      hardwareBands: eq.hasHardwareEq ? eq.hardwareBandCount : 0,
                    ),
                  ],
                ),
              ),

              // ── Curve ─────────────────────────────────────────────
              _Section(
                id: 'curve',
                title: 'Frequency response',
                subtitle: 'Live preview of your curve',
                icon: Icons.show_chart_rounded,
                open: _isOpen('curve'),
                onToggle: () => _toggle('curve'),
                child: Column(
                  children: [
                    SizedBox(
                      height: 128,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          child: CustomPaint(
                            painter: _ResponseCurvePainter(
                              points: eq.responseCurvePoints(),
                              minDb: EqualizerProvider.studioMinDb,
                              maxDb: EqualizerProvider.studioMaxDb,
                              color: scheme.primary,
                              gridColor:
                                  scheme.outlineVariant.withValues(alpha: 0.45),
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
                    const SizedBox(height: 8),
                    _Hint(
                      'The line is the combined tone shape. Above the middle = boost; '
                      'below = cut. Small moves are usually enough.',
                    ),
                  ],
                ),
              ),

              // ── Preamp (knob) ──────────────────────────────────────
              _Section(
                id: 'preamp',
                title: 'Preamp (DVC)',
                subtitle:
                    '${eq.preamp >= 0 ? '+' : ''}${eq.preamp.toStringAsFixed(1)} dB',
                icon: Icons.dialpad_rounded,
                open: _isOpen('preamp'),
                onToggle: () => _toggle('preamp'),
                child: Column(
                  children: [
                    Center(
                      child: EqKnob(
                        value: eq.preamp.clamp(-6.0, 6.0),
                        min: -6,
                        max: 6,
                        label: 'Preamp',
                        unit: ' dB',
                        enabled: eq.isEnabled,
                        size: 96,
                        onChanged: (v) {
                          eq.setPreamp(v);
                          // 64-bit Direct Volume Control when native lib is present
                          DspEngineBridge.instance.setVolumeRampedDb(v);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Hint(
                      'Drag the knob up/down. 0 dB is neutral. '
                      'When DSP ENGINE is loaded, this uses 64-bit Direct Volume Control '
                      'for smoother, cleaner level changes. Prefer cuts over big boosts '
                      'to avoid clipping on phones.',
                    ),
                  ],
                ),
              ),

              // ── Presets ───────────────────────────────────────────
              _Section(
                id: 'presets',
                title: 'Presets',
                subtitle: eq.preset,
                icon: Icons.library_music_rounded,
                open: _isOpen('presets'),
                onToggle: () => _toggle('presets'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hint(
                      'Choose a category, then a preset. Use the bookmark icon '
                      'in the app bar to save your own curve.',
                    ),
                    const SizedBox(height: 10),
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
                                onSelected: (_) => setState(() {
                                  _category = c;
                                  _categorySynced = true;
                                }),
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
                            onSelected:
                                eq.isEnabled ? (_) => eq.applyPreset(p.name) : null,
                            onDeleted: p.isCustom
                                ? () => eq.deleteCustomPreset(p.name)
                                : null,
                            deleteIcon: p.isCustom
                                ? const Icon(Icons.close, size: 16)
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Studio bands ──────────────────────────────────────
              _Section(
                id: 'bands',
                title: 'Studio bands (${eq.studioBandCount})',
                subtitle: 'Fine-tune individual frequencies',
                icon: Icons.tune_rounded,
                open: _isOpen('bands'),
                onToggle: () => _toggle('bands'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hint(
                      'Scroll sideways. Drag a slider up to boost that frequency, '
                      'down to cut. Extreme boosts can distort — start small.',
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 280,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final band in eq.studioBands)
                              SizedBox(
                                width: 36,
                                child: _StudioBandSlider(
                                  band: band,
                                  enabled: eq.isEnabled,
                                  onChanged: (v) =>
                                      eq.setStudioBandGain(band.index, v),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (eq.preset == 'Custom')
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Custom curve · bookmark icon saves a preset',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),

              // ── Smart options ─────────────────────────────────────
              _Section(
                id: 'smart',
                title: 'Smart EQ',
                subtitle: 'Learning & device profiles',
                icon: Icons.auto_awesome_rounded,
                open: _isOpen('smart'),
                onToggle: () => _toggle('smart'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Learned EQ leans'),
                      subtitle: const Text(
                        'Remembers a preset for a song or artist and applies it next time.',
                      ),
                      value: eq.learnedEqEnabled,
                      onChanged: eq.setLearnedEqEnabled,
                    ),
                    if (eq.learnedEqEnabled)
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () =>
                                eq.rememberLeanForCurrent(forArtist: false),
                            child: const Text('Remember for this song'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                eq.rememberLeanForCurrent(forArtist: true),
                            child: const Text('Remember for artist'),
                          ),
                        ],
                      ),
                    const Divider(height: 24),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bluetooth EQ profiles'),
                      subtitle: const Text(
                        'Apply a preset when headphones, car, or speaker is detected. '
                        'Song/artist leans still win when learned EQ is on.',
                      ),
                      value: eq.btProfilesEnabled,
                      onChanged: eq.setBtProfilesEnabled,
                    ),
                    if (eq.btProfilesEnabled)
                      for (final ctx in [
                        BluetoothAudioContext.headphones,
                        BluetoothAudioContext.car,
                        BluetoothAudioContext.speaker,
                      ])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(switch (ctx) {
                            BluetoothAudioContext.headphones => 'Headphones',
                            BluetoothAudioContext.car => 'Car',
                            BluetoothAudioContext.speaker => 'Speaker',
                            _ => ctx.name,
                          }),
                          subtitle: Text(eq.btPresetFor(ctx) ?? 'No preset'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (name) => eq.setBtPreset(ctx, name),
                            itemBuilder: (_) => [
                              for (final p in eq.allPresets)
                                PopupMenuItem(
                                  value: p.name,
                                  child: Text(p.name),
                                ),
                            ],
                            child: const Icon(Icons.tune_rounded),
                          ),
                        ),
                  ],
                ),
              ),

              // ── Advanced native ───────────────────────────────────
              _Section(
                id: 'advanced',
                title: 'Advanced native path',
                subtitle: 'Optional deeper processing',
                icon: Icons.memory_rounded,
                open: _isOpen('advanced'),
                onToggle: () => _toggle('advanced'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Native multi-band DSP'),
                      subtitle: const Text(
                        'Uses the device multi-band path when available (API 28+). '
                        'Leave off if playback becomes unstable — hardware EQ still works.',
                      ),
                      value: eq.nativeDspUserEnabled,
                      onChanged: eq.setNativeDspEnabled,
                    ),
                    _Hint(
                      'DSP ENGINE (64-bit DVC) handles clean volume/preamp when the '
                      'native library is packaged. Band shaping still uses the Resonate '
                      'studio model mapped to Android EQ. More native EQ stages can be '
                      'added in DSP ENGINE later without changing this screen layout.',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: ListView(
          shrinkWrap: true,
          children: const [
            Text('How to use the Equalizer',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('1. Turn Enable equalizer on.'),
            SizedBox(height: 8),
            Text('2. Open Presets, pick a category (Genre, Bass, Voice…), then a name.'),
            SizedBox(height: 8),
            Text('3. Optional: open Preamp and drag the knob for overall level (DVC).'),
            SizedBox(height: 8),
            Text('4. Optional: open Studio bands to tweak one frequency at a time.'),
            SizedBox(height: 8),
            Text('5. Tap sections to collapse them and keep the screen tidy.'),
            SizedBox(height: 8),
            Text('6. Bookmark saves your curve; reset returns to Flat.'),
            SizedBox(height: 16),
            Text(
              'Safe listening: prefer small boosts and use cuts to reduce mud or harshness. '
              'Big boosts on bass can rattle speakers and drain battery.',
            ),
          ],
        ),
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

// ─── Section shell ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  const _Section({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon, color: scheme.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle),
            trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
            onTap: onToggle,
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class _EngineCard extends StatelessWidget {
  final bool dspAvailable;
  final String dspVersion;
  final String dspId;
  final String studioId;
  final bool nativeActive;
  final int hardwareBands;

  const _EngineCard({
    required this.dspAvailable,
    required this.dspVersion,
    required this.dspId,
    required this.studioId,
    required this.nativeActive,
    required this.hardwareBands,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                dspAvailable ? Icons.check_circle_rounded : Icons.info_outline,
                size: 18,
                color: dspAvailable ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dspAvailable
                      ? 'DSP ENGINE $dspVersion'
                      : 'DSP ENGINE not loaded yet',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dspAvailable
                ? '$dspId · 64-bit DVC for preamp\nStudio model: $studioId\nHardware bands: $hardwareBands${nativeActive ? ' · native multi-band on' : ''}'
                : 'Using studio model ($studioId) + Android EQ. '
                    'Package libdsp_engine.so to enable 64-bit DVC.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
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
  final List<Offset> points;
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
      final y = size.height *
          (1 - ((p.dy - minDb) / (maxDb - minDb)).clamp(0.0, 1.0));
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
  bool shouldRepaint(covariant _ResponseCurvePainter old) =>
      old.points != points || old.enabled != enabled || old.color != color;
}
