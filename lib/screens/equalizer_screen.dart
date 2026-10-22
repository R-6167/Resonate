import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_effects_provider.dart';
import '../providers/equalizer_provider.dart';
import '../providers/music_provider.dart';
import '../services/audio_effects_bridge.dart';

/// Glass Equalizer — packed, creative, readable for everyone.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  bool _statusBusy = false;
  String? _statusMessage;
  Map<String, dynamic>? _liveStatus;

  // Resonate brand accents (logo: blue / violet / pink / orange)
  static const _cBlue = Color(0xFF5B8CFF);
  static const _cViolet = Color(0xFF9B6DFF);
  static const _cPink = Color(0xFFFF6BB5);
  static const _cOrange = Color(0xFFFF8A4C);

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
            tooltip: 'Save custom profile',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => _saveCustom(context),
          ),
          IconButton(
            tooltip: 'Reset studio bands',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => context.read<EqualizerProvider>().resetStudioBandsToNeutral(),
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
                final active =
                    (_liveStatus?['activeEngines'] as num?)?.toInt() ?? 0;
                final music = context.watch<MusicProvider>();
                final live = eq.isEnabled && (active > 0 || music.isPlaying || eq.hasHardwareEq || (_liveStatus?['eqEnabled'] == true));

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    // —— Power + Engine ——
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.graphic_eq_rounded, color: _cBlue),
                            title: const Text(
                              'Resonate tone shaping',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text('Always active · ${eq.studioBandCount} studio bands'),
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

                    // —— Resonate sound —— 
                    _GlassCard(
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [_cBlue, _cViolet, _cPink],
                              ),
                            ),
                            child: const Icon(Icons.graphic_eq_rounded,
                                color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Resonate sound',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text(
                                  'The original smooth Resonate tuning. Shape the studio bands below to make it yours.',
                                  style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: eq.preset == 'Resonate Signature'
                                ? 'Resonate sound selected'
                                : 'Restore Resonate sound',
                            onPressed: eq.isEnabled
                                ? () => eq.applyPreset('Resonate Signature')
                                : null,
                            icon: Icon(
                              eq.preset == 'Resonate Signature'
                                  ? Icons.check_circle_rounded
                                  : Icons.restart_alt_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
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


                    // —— Custom profiles —— 
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your custom profiles',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            'Save the Studio bands you shape with the bookmark button. Your profiles stay available here.',
                            style: Theme.of(context).textTheme.bodySmall),
                          if (eq.customPresets.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final profile in eq.customPresets)
                                  FilterChip(
                                    label: Text(profile.name),
                                    selected: eq.preset == profile.name,
                                    onSelected: eq.isEnabled
                                        ? (_) => eq.applyPreset(profile.name)
                                        : null,
                                    onDeleted: () => eq.deleteCustomPreset(profile.name),
                                    deleteIcon: const Icon(Icons.close, size: 16),
                                  ),
                              ],
                            ),
                          ] else ...[
                            const SizedBox(height: 10),
                            const Text(
                              'No custom profiles yet. Shape the bands, then tap the bookmark icon to save one.'),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // —— Colour effects (Bass / Width / Reverb) ——
                    // Loudness was removed: DSP preamp owns overall level.
                    Consumer<AudioEffectsProvider>(
                      builder: (context, fx, _) {
                        String pct(double v) => '${(v * 100).round()}%';
                        return _GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                secondary: Icon(Icons.palette_rounded,
                                    color: _cViolet),
                                title: const Text('Colour effects',
                                    style: TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  fx.effectsEnabled
                                      ? 'Bass · width · reverb on the current output'
                                      : 'Off — pure tone from EQ only',
                                ),
                                value: fx.effectsEnabled,
                                onChanged: fx.setEffectsEnabled,
                              ),
                              if (fx.effectsEnabled) ...[
                                const Divider(height: 18),
                                _FxSlider(
                                  icon: Icons.speaker_rounded,
                                  title: 'Bass boost',
                                  hint: 'Extra low-end weight for earbuds / small speakers',
                                  value: fx.bassBoost,
                                  color: _cOrange,
                                  enabled: fx.effectsEnabled,
                                  onChanged: fx.setBassBoost,
                                  label: pct(fx.bassBoost),
                                ),
                                _FxSlider(
                                  icon: Icons.surround_sound_rounded,
                                  title: 'Width',
                                  hint: 'Stereo space / virtualizer',
                                  value: fx.virtualizer,
                                  color: _cBlue,
                                  enabled: fx.effectsEnabled,
                                  onChanged: fx.setVirtualizer,
                                  label: pct(fx.virtualizer),
                                ),
                                _FxSlider(
                                  icon: Icons.water_drop_outlined,
                                  title: 'Reverb',
                                  hint: 'A light room air — keep low for clarity',
                                  value: fx.reverb,
                                  color: _cPink,
                                  enabled: fx.effectsEnabled,
                                  onChanged: fx.setReverb,
                                  label: pct(fx.reverb),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: fx.reset,
                                    icon: const Icon(Icons.refresh_rounded, size: 18),
                                    label: const Text('Reset colour'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),

                    const SizedBox(height: 20),
                    Text(
                      'Resonate sound, your studio bands, your own custom profile.',
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
                title: 'Start with Resonate sound',
                body:
                    'Resonate tone shaping is always active. Fine-tune the studio bands and save your own custom profile when it feels right.',
              ),
              const _HelpStep(
                n: '2',
                title: 'Create your sound',
                body:
                    'Start with Resonate sound, shape the studio bands, and save a custom profile using the bookmark button.',
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
                    'Use the bookmark icon to save the studio-band curve as a named custom profile.',
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
        title: const Text('Save custom profile'),
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
    final savedName =
        await context.read<EqualizerProvider>().saveCustomPreset(name);
    if (!context.mounted || savedName == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved “$savedName”')),
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


class _FxSlider extends StatelessWidget {
  const _FxSlider({
    required this.icon,
    required this.title,
    required this.hint,
    required this.value,
    required this.color,
    required this.enabled,
    required this.onChanged,
    required this.label,
  });

  final IconData icon;
  final String title;
  final String hint;
  final double value;
  final Color color;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(hint, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            divisions: 20,
            activeColor: color,
            label: label,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
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
