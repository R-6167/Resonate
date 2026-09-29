#!/usr/bin/env python3
from pathlib import Path
NL = chr(10)
ROOT = Path(__file__).resolve().parents[1]
changed = []

def patch(path, old, new, label):
    p = ROOT / path
    text = p.read_text()
    if old not in text:
        print('skip', label)
        return
    p.write_text(text.replace(old, new, 1))
    changed.append(label)
    print('patched', label)

old_main = (
    '        // Equal-power: cos out / sin in — smooth energy, no mid-fade dip.' + NL +
    '        final angle = t * (math.pi / 2.0);' + NL +
    '        final outGain = math.cos(angle);' + NL +
    '        final inGain = math.sin(angle);' + NL +
    '        final outVol = (base * outGain).clamp(0.0, 1.0);' + NL +
    '        final inVol = (master * inGain).clamp(0.0, 1.0);'
)
new_main = (
    '        // Soft-outgoing equal-power: keep outgoing louder longer.' + NL +
    '        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);' + NL +
    '        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);' + NL +
    '        final outGain = math.cos(outT * (math.pi / 2.0));' + NL +
    '        final inGain = math.sin(inT * (math.pi / 2.0));' + NL +
    '        final outVol = (base * outGain).clamp(0.0, 1.0);' + NL +
    '        final inVol = (master * inGain).clamp(0.0, 1.0);'
)
patch('lib/providers/music_provider.dart', old_main, new_main, 'crossfade main soft-outgoing')

old_lin = (
    '        try {' + NL +
    '          await outgoing.setVolume((startOut * (1.0 - t)).clamp(0.0, 1.0));' + NL +
    '        } catch (_) {}' + NL +
    '        try {' + NL +
    '          await incoming.setVolume((master * t).clamp(0.0, 1.0));' + NL +
    '        } catch (_) {}'
)
new_lin = (
    '        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);' + NL +
    '        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);' + NL +
    '        try {' + NL +
    '          await outgoing.setVolume((startOut * math.cos(outT * (math.pi / 2.0))).clamp(0.0, 1.0));' + NL +
    '        } catch (_) {}' + NL +
    '        try {' + NL +
    '          await incoming.setVolume((master * math.sin(inT * (math.pi / 2.0))).clamp(0.0, 1.0));' + NL +
    '        } catch (_) {}'
)
patch('lib/providers/music_provider.dart', old_lin, new_lin, 'repeat-self soft-outgoing')

patch(
    'lib/screens/settings_screen.dart',
    "              _item(context, 'Effects', 'Loudness and audio processing', Icons.tune_rounded, const AudioEffectsScreen())," + NL,
    '              // Effects moved into Equalizer (Bass / Width / Reverb). Loudness retired.' + NL,
    'settings remove Effects',
)

patch(
    'lib/screens/settings_screen.dart',
    "_item(context, 'Equalizer', 'Main sound profile', Icons.equalizer_rounded, const EqualizerScreen()),",
    "_item(context, 'Equalizer', 'Tone, preamp, bass, width & reverb', Icons.equalizer_rounded, const EqualizerScreen()),",
    'settings equalizer subtitle',
)

# Equalizer glass from b64 chunks if present
import base64
dst = ROOT / 'lib/screens/equalizer_screen.dart'
parts = []
for i in range(3):
    cp = Path(__file__).resolve().parent / f'equalizer_screen_glass_{i}.b64'
    if cp.exists():
        parts.append(cp.read_text().strip())
if parts:
    dst.write_bytes(base64.b64decode(''.join(parts).encode()))
    changed.append('equalizer glass')
    print('wrote equalizer from b64 chunks')
else:
    print('no b64 equalizer chunks')

print('TOTAL', changed)
