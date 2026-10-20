#!/usr/bin/env python3
"""Add Colour effects (Bass/Width/Reverb) to glass Equalizer. Loudness stays retired."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = ROOT / "lib/screens/equalizer_screen.dart"
t = p.read_text()

if "Colour effects" in t and "AudioEffectsProvider" in t:
    print("already has Colour effects")
else:
    # imports
    if "audio_effects_provider.dart" not in t:
        t = t.replace(
            "import '../providers/equalizer_provider.dart';",
            "import '../providers/audio_effects_provider.dart';\n"
            "import '../providers/equalizer_provider.dart';",
        )
    if "music_provider.dart" not in t:
        t = t.replace(
            "import '../providers/equalizer_provider.dart';",
            "import '../providers/equalizer_provider.dart';\n"
            "import '../providers/music_provider.dart';",
        )

    # live badge
    if "final live = active > 0 && eq.isEnabled;" in t:
        t = t.replace(
            "final live = active > 0 && eq.isEnabled;",
            "final music = context.watch<MusicProvider>();\n"
            "                final live = eq.isEnabled &&\n"
            "                    (active > 0 || music.isPlaying ||\n"
            "                     eq.hasHardwareEq || (_liveStatus?['eqEnabled'] == true));",
        )

    marker = "                    // —— Smart options ——"
    if marker not in t:
        # try alternate dash
        for m in ["// — Smart options", "// Smart options", "Learned EQ leans"]:
            if m in t:
                print("found alternate marker", m)
                break
        else:
            print("NO marker for Smart options — dump snippet")
            i = t.find("Learned")
            print(repr(t[max(0,i-200):i+80]) if i>=0 else "no Learned")
            raise SystemExit(1)

    effects = r'''
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
                                secondary: Icon(Icons.auto_fix_rounded,
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

'''

    if "Colour effects" not in t:
        if marker in t:
            t = t.replace(marker, effects + marker, 1)
        else:
            # insert before Learned EQ leans card
            lean = "title: const Text('Learned EQ leans'"
            idx = t.find(lean)
            if idx < 0:
                raise SystemExit("cannot find insert point")
            # find preceding _GlassCard
            card = t.rfind("_GlassCard(", 0, idx)
            # find the comment or SizedBox before that card
            insert_at = t.rfind("const SizedBox(height: 14)", 0, card)
            if insert_at < 0:
                insert_at = card
            t = t[:insert_at] + effects + t[insert_at:]

    # _FxSlider widget
    if "class _FxSlider" not in t:
        fx_w = r'''
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

'''
        if "class _Badge" in t:
            t = t.replace("class _Badge", fx_w + "class _Badge", 1)
        else:
            t = t + "\n" + fx_w

    p.write_text(t)
    print("patched equalizer colour effects", "Colour effects" in t)

# Settings: ensure Effects nav is gone
sp = ROOT / "lib/screens/settings_screen.dart"
if sp.exists():
    st = sp.read_text()
    if "AudioEffectsScreen()" in st and "Effects" in st:
        st2 = st.replace(
            "_item(context, 'Effects', 'Loudness and audio processing', Icons.tune_rounded, const AudioEffectsScreen()),\n",
            "// Effects live on Equalizer (Bass / Width / Reverb). Loudness retired.\n",
        )
        if st2 == st:
            st2 = st.replace(
                "_item(context, 'Effects', 'Loudness and audio processing', Icons.tune_rounded, const AudioEffectsScreen()),",
                "// Effects live on Equalizer",
            )
        st2 = st2.replace(
            "_item(context, 'Equalizer', 'Main sound profile', Icons.equalizer_rounded, const EqualizerScreen())",
            "_item(context, 'Equalizer', 'Tone, preamp, bass, width & reverb', Icons.equalizer_rounded, const EqualizerScreen())",
        )
        sp.write_text(st2)
        print("settings updated")
    else:
        print("settings already clean or missing Effects")

print("done")
