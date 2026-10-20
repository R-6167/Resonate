import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
                    Text(
                      'Choose how Resonate responds to notification ducking, calls and other apps. '
                      'Android does not identify every focus-loss source consistently, so automatic resume is deliberately limited by the selected level.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Automatic response'),
                      subtitle: Text(
                        music.audioFocusAutomationEnabled
                            ? 'Resonate applies the selected focus level automatically.'
                            : 'Manual mode: Resonate still pauses on full focus loss for safety, but will not automatically duck or resume.',
                      ),
                      value: music.audioFocusAutomationEnabled,
                      onChanged: (value) => music.setAudioFocusAutomation(automatic: value),
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
                      'Duck notifications more deeply. Pause on full focus loss; require manual resume.',
                    ),
                    _level(
                      context,
                      music,
                      2,
                      'Level 2 · Conservative',
                      'Duck notifications moderately. Pause on calls or other full focus loss; do not auto-resume.',
                    ),
                    _level(
                      context,
                      music,
                      3,
                      'Level 3 · Short auto-resume',
                      'Resume only after focus returns from a short interruption (up to 30 seconds).',
                    ),
                    _level(
                      context,
                      music,
                      4,
                      'Level 4 · Adaptive',
                      'Resume after focus returns from an interruption of up to 3 minutes. Longer interruptions require manual resume.',
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
              Consumer<EqualizerProvider>(
                builder: (context, eq, _) => ResonateGlassCard(
                  blurEnabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EQ and output level', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      const Text(
                        'Estimate headroom from the largest positive software EQ band and lower the effective preamp to reduce clipping risk. '
                        'This is a conservative estimate, not a measurement of the device output; compensation is bounded by the DSP preamp floor.',
                      ),
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
