import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/bluetooth_provider.dart';
import '../providers/equalizer_provider.dart';
import '../services/audio_effects_bridge.dart';

/// Glass Equalizer — packed, creative, readable for everyone.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  String _category = 'Genre';
  bool _categorySynced = false;
  bool _showAdvanced = false;
  bool _showBtProfiles = false;
  bool _statusBusy = false;
  String? _statusMessage;
  Map<String, dynamic>? _liveStatus;

  // Resonate brand accents (logo: blue / violet / pink / orange)
  static const _cBlue = Color(0xFF5B8CFF);
  static const _cViolet = Color(0xFF9B6DFF);
  static const _cPink = Color(0xFFFF6BB5);
  static const _cOrange = Color(0xFFFF8A4C);

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

  Future<void> _refreshLiveStatus() async {
    setState(() {
      _statusBusy = true;
      _statusMessage = null;
    });
    try {
      final s = await AudioEffectsBridge.getLiveDspStatus();
      if (!mounted) return;
      setState(() {
        _liveStatus = s;
        _statusBusy = false;
        if (s == null) {
          _statusMessage =
              'Tone shaping is ready. Status updates after music starts playing.';
        } else {
          final active = (s['activeEngines'] as num?)?.toInt() ?? 0;
          final tripped = s['gateTripped'] == true;
          if (tripped) {
            _statusMessage =
                'Safety mode is on — sound still plays with a simpler path. '
                'Restart the app if this stays on.';
          } else if (active > 0) {
            _statusMessage =
                'Resonate DSP is shaping your music right now '
                '(${active == 2 ? 'both players during crossfade' : 'live path'}).';
          } else {
            _statusMessage =
                'Engine is standing by. Press play — EQ applies automatically.';
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusBusy = false;
        _statusMessage =
            'Could not read engine status. Your equalizer still works while music plays.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLiveStatus());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
      body: Stack(
        children: [
          // Soft brand wash
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF0E0B18),
                          _cViolet.withValues(alpha: 0.18),
                          _cBlue.withValues(alpha: 0.12),
                          const Color(0xFF0A0A12),
                        ]
                      : [
                          scheme.surface,
                          _cBlue.withValues(alpha: 0.08),
                          _cPink.withValues(alpha: 0.06),
                          scheme.surface,
                        ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Consumer<EqualizerProvider>(
              builder: (context, eq, _) {
                _syncCategoryFromPreset(eq);
                final categories = eq.categories;
                if (categories.isNotEmpty && !categories.contains(_category)) {
                  _category = categories.first;
                }
                final presets = eq.presetsInCategory(_category);
                final active =
                    (_liveStatus?['activeEngines'] as num?)?.toInt() ?? 0;
                final live = active > 0 && eq.isEnabled;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    // —— Power + Engine ——
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            secondary: Icon(
                              Icons.graphic_eq_rounded,
                              color: eq.isEnabled ? _cBlue : scheme.outline,
                            ),
                            title: const Text(
                              'Equalizer',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              eq.isEnabled
                                  ? 'Tone shaping on · ${eq.studioBandCount} studio bands'
                                  : 'Off — music plays with a flat curve',
                            ),
                            value: eq.isEnabled,
                            onChanged: (v) async {
                              await eq.setEnabled(v);
                              await _refreshLiveStatus();
                            },
                          ),
                          const Divider(height: 20),
                          _EngineStrip(
                            live: live,
                            hardwareBands: eq.hasHardwareEq
                                ? eq.hardwareBandCount
                                : 0,
                            activeEngines: active,
                            onRefresh: _statusBusy ? null : _refreshLiveStatus,
                            busy: _statusBusy,
                          ),
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _statusMessage!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // —— Curve ——
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Frequency response',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 112,
                            child: CustomPaint(
                              painter: _ResponseCurvePainter(
                                points: eq.responseCurvePoints(),
                                minDb: EqualizerProvider.studioMinDb,
                                maxDb: EqualizerProvider.studioMaxDb,
                                color: _cBlue,
                                accent: _cPink,
                                gridColor: scheme.outlineVariant
                                    .withValues(alpha: 0.4),
                                enabled: eq.isEnabled,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Bass', style: Theme.of(context).textTheme.labelSmall),
                              Text('Mids', style: Theme.of(context).textTheme.labelSmall),
                              Text('Treble', style: Theme.of(context).textTheme.labelSmall),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // —— Preamp ——
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.volume_up_rounded,
                                  size: 20, color: _cOrange),
                              const SizedBox(width: 8),
                              Text(
                                'Preamp',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              Text(
                                '${eq.preamp >= 0 ? '+' : ''}${eq.preamp.toStringAsFixed(1)} dB',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: _cOrange,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                          Slider(
                            value: eq.preamp.clamp(-6.0, 6.0),
                            min: -6,
                            max: 6,
                            divisions: 24,
                            activeColor: _cOrange,
                            onChanged: eq.isEnabled ? eq.setPreamp : null,
                          ),
                          Text(
                            'Overall loudness before the bands. 0 is neutral. '
                            'Cuts stay gentle; boosts are limited so the phone does not crackle.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // —— Presets ——
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Presets',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
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
                                  onSelected: eq.isEnabled
                                      ? (_) => eq.applyPreset(p.name)
                                      : null,
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
                    const SizedBox(height: 14),

                    // —— Studio bands ——
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Studio bands',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Swipe sideways for every band. Drag a slider up for more of that frequency, down for less.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 260,
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
                                        accent: _cViolet,
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
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Custom curve — tap the bookmark icon to save',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: _cPink),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // —— Smart options ——
                    _GlassCard(
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            secondary: Icon(Icons.auto_awesome_rounded,
                                color: _cPink),
                            title: const Text('Learned EQ leans',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text(
                              'Remember a preset for a song or artist and restore it next time.',
                            ),
                            value: eq.learnedEqEnabled,
                            onChanged: eq.setLearnedEqEnabled,
                          ),
                          if (eq.learnedEqEnabled)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => eq.rememberLeanForCurrent(
                                        forArtist: false),
                                    child: const Text('This song'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => eq.rememberLeanForCurrent(
                                        forArtist: true),
                                    child: const Text('This artist'),
                                  ),
                                ],
                              ),
                            ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            secondary: Icon(Icons.bluetooth_audio_rounded,
                                color: _cBlue),
                            title: const Text('Bluetooth profiles',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text(
                              'Optional presets for headphones, car, or speaker.',
                            ),
                            value: eq.btProfilesEnabled,
                            onChanged: (v) async {
                              await eq.setBtProfilesEnabled(v);
                              setState(() => _showBtProfiles = v);
                            },
                          ),
                          if (eq.btProfilesEnabled || _showBtProfiles)
                            for (final ctx in [
                              BluetoothAudioContext.headphones,
                              BluetoothAudioContext.car,
                              BluetoothAudioContext.speaker,
                            ])
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(switch (ctx) {
                                  BluetoothAudioContext.headphones =>
                                    'Headphones',
                                  BluetoothAudioContext.car => 'Car',
                                  BluetoothAudioContext.speaker => 'Speaker',
                                  _ => ctx.name,
                                }),
                                subtitle:
                                    Text(eq.btPresetFor(ctx) ?? 'No preset'),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (name) =>
                                      eq.setBtPreset(ctx, name),
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
                    const SizedBox(height: 14),

                    // —— Advanced (collapsed) ——
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () => setState(
                                () => _showAdvanced = !_showAdvanced),
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                              children: [
                                Icon(Icons.tune_rounded, color: _cViolet),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Advanced',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700),
                                      ),
                                      Text(
                                        'Optional multi-band path & engine check',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  _showAdvanced
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                ),
                              ],
                            ),
                          ),
                          if (_showAdvanced) ...[
                            const SizedBox(height: 12),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Extra multi-band path'),
                              subtitle: const Text(
                                'Uses an additional device path when available. '
                                'Leave off if playback ever stutters — '
                                'Resonate DSP Engine still shapes the sound.',
                              ),
                              value: eq.nativeDspUserEnabled,
                              onChanged: eq.setNativeDspEnabled,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Engine check',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Confirms the live audio path is healthy. '
                              'You do not need this for everyday listening.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 10),
                            FilledButton.tonalIcon(
                              onPressed:
                                  _statusBusy ? null : _refreshLiveStatus,
                              icon: _statusBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.health_and_safety_outlined),
                              label: Text(
                                _statusBusy
                                    ? 'Checking…'
                                    : 'Check engine status',
                              ),
                            ),
                            if (_statusMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  _statusMessage!,
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Tip: turn EQ on, pick a preset, then nudge preamp if the whole mix feels quiet or loud.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How to use the Equalizer',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              const _HelpStep(
                n: '1',
                title: 'Turn it on',
                body:
                    'Flip the Equalizer switch at the top. Off means a flat, uncolored sound.',
              ),
              const _HelpStep(
                n: '2',
                title: 'Pick a preset',
                body:
                    'Browse categories (Genre, Mood, …) then tap a chip. '
                    'Start with something close to your taste.',
              ),
              const _HelpStep(
                n: '3',
                title: 'Fine-tune',
                body:
                    'Preamp moves overall loudness. Studio bands target bass, mids, and treble. '
                    'Small moves sound more natural than big ones.',
              ),
              const _HelpStep(
                n: '4',
                title: 'Save your curve',
                body:
                    'When the preset says Custom, use the bookmark icon to save a name.',
              ),
              const _HelpStep(
                n: '5',
                title: 'Optional extras',
                body:
                    'Learned leans remember a song or artist. Bluetooth profiles '
                    'can switch presets for headphones, car, or speaker. '
                    'Advanced is optional — everyday listening does not need it.',
              ),
              const SizedBox(height: 8),
              Text(
                'Engine',
                style: Theme.of(ctx)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Resonate uses its own DSP Engine to shape audio while you listen. '
                'A green Live badge means the engine is actively processing. '
                'If music is paused, the engine may show Standby — that is normal.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            ],
          ),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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

// —— Glass shell ——

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: (isDark ? Colors.white : scheme.surface)
                .withValues(alpha: isDark ? 0.08 : 0.55),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _EngineStrip extends StatelessWidget {
  const _EngineStrip({
    required this.live,
    required this.hardwareBands,
    required this.activeEngines,
    required this.onRefresh,
    required this.busy,
  });

  final bool live;
  final int hardwareBands;
  final int activeEngines;
  final VoidCallback? onRefresh;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFF5B8CFF), Color(0xFF9B6DFF)],
            ),
          ),
          child: const Icon(Icons.memory_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resonate DSP Engine',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                hardwareBands > 0
                    ? 'In-house processing · $hardwareBands device bands available'
                    : 'In-house processing · attaches fully once playback starts',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Badge(
                    label: live ? 'Live' : 'Standby',
                    color: live
                        ? const Color(0xFF3DDC97)
                        : scheme.outline,
                  ),
                  if (activeEngines > 0)
                    _Badge(
                      label: activeEngines == 2 ? 'A + B' : '1 path',
                      color: const Color(0xFF5B8CFF),
                    ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh status',
          onPressed: onRefresh,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep(
      {required this.n, required this.title, required this.body});
  final String n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            child: Text(n,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudioBandSlider extends StatelessWidget {
  final StudioBand band;
  final bool enabled;
  final Color accent;
  final ValueChanged<double> onChanged;

  const _StudioBandSlider({
    required this.band,
    required this.enabled,
    required this.accent,
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
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accent,
                thumbColor: accent,
              ),
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
  final Color accent;
  final Color gridColor;
  final bool enabled;

  _ResponseCurvePainter({
    required this.points,
    required this.minDb,
    required this.maxDb,
    required this.color,
    required this.accent,
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

    final fillPath = Path.from(path)
      ..lineTo(size.width, zeroY)
      ..lineTo(0, zeroY)
      ..close();
    final lineColor = enabled ? color : color.withValues(alpha: 0.35);
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.32),
            accent.withValues(alpha: 0.04),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ResponseCurvePainter old) =>
      old.points != points || old.enabled != enabled || old.color != color;
}
