import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/bluetooth_provider.dart';
import '../providers/equalizer_provider.dart';
import '../services/dsp_engine_bridge.dart';
import '../services/dsp_process_path.dart';
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
  String? _processTestResult;
  bool _processTesting = false;

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
                          DspEngineBridge.instance.setVolumeRampedDb(v);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Hint(
                      'Drag the knob up/down. 0 dB is neutral. '
                      'When DSP ENGINE is loaded, this uses 64-bit Direct Volume Control. '
                      'Prefer cuts over big boosts to avoid clipping on phones.',
                    ),
                  ],
                ),
              ),
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
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _processTesting
                          ? null
                          : () async {
                              setState(() {
                                _processTesting = true;
                                _processTestResult = null;
                              });
                              final status =
                                  await DspProcessPath.instance.runSelfTest();
                              if (!mounted) return;
                              setState(() {
                                _processTesting = false;
                                _processTestResult = status.summary;
                              });
                            },
                      icon: _processTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.science_outlined),
                      label: Text(
                        _processTesting
                            ? 'Running process()…'
                            : 'Test DSP process() path',
                      ),
                    ),
                    if (_processTestResult != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _processTestResult!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    _Hint(
                      'Live playback uses AndroidEqualizer + optional DynamicsProcessing. '
                      'just_audio does not expose a custom ExoPlayer AudioProcessor, so '
                      'dsp_process() cannot sit on the live path without forking the player. '
                      'The test above runs process() on a synthetic buffer to verify the '
                      'native library. A future sink would call the same C ABI on the audio thread.',
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
            Text('6. Bookmark saves a custom preset; reset sets Flat.'),
            SizedBox(height: 16),
            Text(
              'Live tone uses Android hardware EQ (and optional Native multi-band). '
              'DSP ENGINE process() is verified under Advanced → Test.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCustom(BuildContext context) async {
    final eq = context.read<EqualizerProvider>();
    final controller = TextEditingController(text: 'My preset');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await eq.saveCustomPreset(name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved “$name”')),
      );
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            leading: Icon(icon, color: scheme.primary),
            title: Text(title),
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
  const _Hint(this.text);
  final String text;

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
  const _EngineCard({
    required this.dspAvailable,
    required this.dspVersion,
    required this.dspId,
    required this.studioId,
    required this.nativeActive,
    required this.hardwareBands,
  });

  final bool dspAvailable;
  final String dspVersion;
  final String dspId;
  final String studioId;
  final bool nativeActive;
  final int hardwareBands;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dspAvailable ? 'DSP ENGINE loaded' : 'DSP ENGINE not loaded',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: dspAvailable ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text('Id: $dspId', style: Theme.of(context).textTheme.bodySmall),
          Text('Version: $dspVersion',
              style: Theme.of(context).textTheme.bodySmall),
          Text('Studio: $studioId',
              style: Theme.of(context).textTheme.bodySmall),
          Text(
            hardwareBands > 0
                ? 'Hardware bands: $hardwareBands'
                : 'Hardware EQ: waiting for playback',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (nativeActive)
            Text('Native path active',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _StudioBandSlider extends StatelessWidget {
  const _StudioBandSlider({
    required this.band,
    required this.enabled,
    required this.onChanged,
  });

  final StudioBand band;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: Slider(
              value: band.gainDb.clamp(
                EqualizerProvider.studioMinDb,
                EqualizerProvider.studioMaxDb,
              ),
              min: EqualizerProvider.studioMinDb,
              max: EqualizerProvider.studioMaxDb,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
        Text(
          band.label,
          style: Theme.of(context).textTheme.labelSmall,
          textAlign: TextAlign.center,
        ),
        Text(
          '${band.gainDb >= 0 ? '+' : ''}${band.gainDb.toStringAsFixed(0)}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _ResponseCurvePainter extends CustomPainter {
  _ResponseCurvePainter({
    required this.points,
    required this.minDb,
    required this.maxDb,
    required this.color,
    required this.gridColor,
    required this.enabled,
  });

  final List<Offset> points;
  final double minDb;
  final double maxDb;
  final Color color;
  final Color gridColor;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * 0.5;
    final range = (maxDb - minDb).abs() < 1e-6 ? 24.0 : (maxDb - minDb);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), grid);

    if (points.length < 2) return;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = p.dx * size.width;
      final y = midY - ((p.dy - 0) / (range / 2)) * (size.height * 0.45);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = enabled ? color : color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ResponseCurvePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.enabled != enabled ||
      oldDelegate.color != color;
}
