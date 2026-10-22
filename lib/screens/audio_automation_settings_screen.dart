import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dsp_settings.dart';
import '../services/audio_effects_bridge.dart';
import '../providers/music_provider.dart';
import '../providers/equalizer_provider.dart';
import '../ui/resonate_glass.dart';
import 'equalizer_screen.dart';
import '../widgets/live_dvc_control.dart';

class AudioAutomationSettingsScreen extends StatelessWidget {
  const AudioAutomationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => ResonateGlassScaffold(
        title: const Text('Audio automation'),
        body: Consumer<MusicProvider>(
          builder: (context, music, _) => ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
            children: [
              ResonateGlassCard(
                blurEnabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Audio focus', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Automatic response'),
                      subtitle: Text(
                        music.audioFocusAutomationEnabled
                            ? 'Use the selected response level automatically.'
                            : 'Manual mode; no automatic ducking or resume.',
                      ),
                      value: music.audioFocusAutomationEnabled,
                      onChanged: (value) => music.setAudioFocusAutomation(automatic: value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.volume_up_rounded),
                      title: const Text('Pause/resume fade'),
                      subtitle: Text(
                        music.pauseResumeFadeEnabled
                            ? 'Brief fade on pause and resume.'
                            : 'Pause and resume immediately.',
                      ),
                      value: music.pauseResumeFadeEnabled,
                      onChanged: music.setPauseResumeFadeEnabled,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ResonateGlassCard(
                blurEnabled: false,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Text('Response level', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    _level(
                      context,
                      music,
                      1,
                      'Level 1 · Gentle',
                      'Stronger notification ducking; manual resume after full focus loss.',
                    ),
                    _level(
                      context,
                      music,
                      2,
                      'Level 2 · Conservative',
                      'Moderate ducking; no automatic resume after full focus loss.',
                    ),
                    _level(
                      context,
                      music,
                      3,
                      'Level 3 · Short auto-resume',
                      'Auto-resume only after interruptions up to 30 seconds.',
                    ),
                    _level(
                      context,
                      music,
                      4,
                      'Level 4 · Adaptive',
                      'Auto-resume up to 3 minutes; longer interruptions need manual resume.',
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Text(
                        'For the current issue where Resonate resumes while another music app is taking over, Level 2 is the safest choice. '
                        'The platform focus event does not reliably say whether the source was a call or another player, so the app cannot safely promise call-only auto-resume yet.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const LiveDvcControl(),
              const SizedBox(height: 12),
              const _LimiterCrossoverControls(),
              const SizedBox(height: 12),
              Consumer<EqualizerProvider>(
                builder: (context, eq, _) => ResonateGlassCard(
                  blurEnabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EQ headroom', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Automatic EQ headroom'),
                        subtitle: Text(
                          eq.autoEqHeadroom
                              ? 'Enabled: positive EQ boosts lower the effective preamp automatically.'
                              : 'Disabled: use the preamp value you set manually.',
                        ),
                        value: eq.autoEqHeadroom,
                        onChanged: eq.setAutoEqHeadroom,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.equalizer_rounded),
                        title: const Text('Equalizer and preamp'),
                        subtitle: const Text('Adjust the current tone and manual preamp'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerScreen())),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _level(BuildContext context, MusicProvider music, int value, String title, String subtitle) =>
      RadioListTile<int>(
        value: value,
        groupValue: music.audioFocusLevel,
        onChanged: (next) {
          if (next != null) music.setAudioFocusAutomation(level: next);
        },
        title: Text(title),
        subtitle: Text(subtitle),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      );
}


class _LimiterCrossoverControls extends StatefulWidget {
  const _LimiterCrossoverControls();

  @override
  State<_LimiterCrossoverControls> createState() =>
      _LimiterCrossoverControlsState();
}

class _LimiterCrossoverControlsState extends State<_LimiterCrossoverControls> {
  static const _profiles = <String, (double, double, double)>{
    'Transparent': (-0.2, -0.2, 160),
    'Balanced': (-0.5, -0.8, 120),
    'Speaker safe': (-1.5, -2.5, 100),
    'Extra headroom': (-3.0, -3.0, 180),
  };

  String _selected = 'Balanced';
  bool _loaded = false;
  String _status = 'Loading saved protection profile…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await DspSettings.load();
      final match = _profiles.entries.where((entry) =>
          (entry.value.$1 - settings.limiterHighCeilingDb).abs() < 0.06 &&
          (entry.value.$2 - settings.limiterLowCeilingDb).abs() < 0.06 &&
          (entry.value.$3 - settings.crossoverHz).abs() < 1.0);
      if (!mounted) return;
      setState(() {
        _selected = match.isEmpty ? 'Custom' : match.first.key;
        _loaded = true;
        _status = 'Saved profile restored. Protection only engages on peaks that reach its threshold.';
      });
      // Reapply the saved native values for current engines and future A/B sinks.
      await AudioEffectsBridge.setLiveDspLimiterCeiling(
        highDb: settings.limiterHighCeilingDb,
        lowDb: settings.limiterLowCeilingDb,
      );
      await AudioEffectsBridge.setLiveDspCrossoverHz(settings.crossoverHz);
    } catch (_) {
      if (mounted) setState(() {
        _loaded = true;
        _status = 'Could not read the saved profile; playback remains available.';
      });
    }
  }

  Future<void> _choose(String name) async {
    final values = _profiles[name];
    if (values == null || !_loaded) return;
    setState(() {
      _selected = name;
      _status = 'Applying $name profile…';
    });
    final high = values.$1;
    final low = values.$2;
    final crossover = values.$3;
    final limiter = await AudioEffectsBridge.setLiveDspLimiterCeiling(
      highDb: high,
      lowDb: low,
    );
    final split = await AudioEffectsBridge.setLiveDspCrossoverHz(crossover);
    try {
      await DspSettings.update((current) => current.copyWith(
        limiterHighCeilingDb: high,
        limiterLowCeilingDb: low,
        crossoverHz: crossover,
      ));
    } catch (_) {
      if (mounted) setState(() => _status = 'Applied for this session, but the profile could not be saved.');
      return;
    }
    if (!mounted) return;
    final active = (limiter?['active'] as num?)?.toInt() ??
        (split?['active'] as num?)?.toInt() ?? 0;
    setState(() => _status = active > 0
        ? '$name applied. It protects peaks; it is not a tone or loudness control.'
        : '$name saved and will apply when a native playback engine starts.');
  }

  Future<void> _reset() => _choose('Balanced');

  @override
  Widget build(BuildContext context) => ResonateGlassCard(
        blurEnabled: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Limiter and crossover',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: _loaded ? _reset : null,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose a protection profile instead of tuning tiny slider changes. '
              'The limiter acts only on peaks; it should not noticeably change the overall tone or loudness. '
              'Use the Equalizer for audible tonal changes.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in _profiles.keys)
                  ChoiceChip(
                    label: Text(name),
                    selected: _selected == name,
                    onSelected: _loaded ? (_) => _choose(name) : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _selected == 'Custom'
                  ? 'Custom saved values detected. Choose a profile to apply a known configuration.'
                  : switch (_selected) {
                      'Transparent' => 'Near-zero ceiling · 160 Hz split',
                      'Balanced' => 'Moderate peak control · 120 Hz split',
                      'Speaker safe' => 'More conservative low-band protection · 100 Hz split',
                      'Extra headroom' => 'Stronger peak reduction · 180 Hz split',
                      _ => 'Select a protection profile.',
                    },
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      );
}
