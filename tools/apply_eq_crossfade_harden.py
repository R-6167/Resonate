#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
changed = []

def sub_file(path, pattern, repl, label, flags=re.M):
    p = ROOT / path
    text = p.read_text()
    new, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n == 0:
        print('skip', label)
        # debug: show nearby lines if marker present
        for marker in ['cos(angle)', 'Equal-power', 'startOut * (1.0', "'Effects'", 'Main sound profile', 'activeEngines']:
            if marker in text and marker in pattern:
                i = text.find(marker)
                print('  near', repr(text[max(0,i-80):i+80]))
        return
    p.write_text(new)
    changed.append(label)
    print('patched', label)

# Main equal-power crossfade
sub_file(
    'lib/providers/music_provider.dart',
    r"final angle = t \* \(math\.pi / 2\.0\);\s*\n\s*final outGain = math\.cos\(angle\);\s*\n\s*final inGain = math\.sin\(angle\);",
    "final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);\n"
    "        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);\n"
    "        final outGain = math.cos(outT * (math.pi / 2.0));\n"
    "        final inGain = math.sin(inT * (math.pi / 2.0));",
    'crossfade main soft-outgoing',
)

# Repeat-self linear ramp
sub_file(
    'lib/providers/music_provider.dart',
    r"await outgoing\.setVolume\(\(startOut \* \(1\.0 - t\)\)\.clamp\(0\.0, 1\.0\)\);\s*\n\s*\} catch \(_\) \{\}\s*\n\s*try \{\s*\n\s*await incoming\.setVolume\(\(master \* t\)\.clamp\(0\.0, 1\.0\)\);",
    "final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);\n"
    "        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);\n"
    "        try {\n"
    "          await outgoing.setVolume((startOut * math.cos(outT * (math.pi / 2.0))).clamp(0.0, 1.0));\n"
    "        } catch (_) {}\n"
    "        try {\n"
    "          await incoming.setVolume((master * math.sin(inT * (math.pi / 2.0))).clamp(0.0, 1.0));",
    'repeat-self soft-outgoing',
)

# Settings: remove Effects item
sub_file(
    'lib/screens/settings_screen.dart',
    r"_item\(context, 'Effects', 'Loudness and audio processing', Icons\.tune_rounded, const AudioEffectsScreen\(\)\),\s*\n",
    "// Effects moved into Equalizer (Bass / Width / Reverb). Loudness retired.\n",
    'settings remove Effects',
)

sub_file(
    'lib/screens/settings_screen.dart',
    r"_item\(context, 'Equalizer', 'Main sound profile', Icons\.equalizer_rounded, const EqualizerScreen\(\)\)",
    "_item(context, 'Equalizer', 'Tone, preamp, bass, width & reverb', Icons.equalizer_rounded, const EqualizerScreen())",
    'settings equalizer subtitle',
)

# EQ imports
sub_file(
    'lib/screens/equalizer_screen.dart',
    r"import '../providers/bluetooth_provider.dart';\nimport '../providers/equalizer_provider.dart';\nimport '../services/audio_effects_bridge.dart';",
    "import '../providers/audio_effects_provider.dart';\n"
    "import '../providers/bluetooth_provider.dart';\n"
    "import '../providers/equalizer_provider.dart';\n"
    "import '../providers/music_provider.dart';\n"
    "import '../services/audio_effects_bridge.dart';",
    'eq imports',
)

# EQ live badge
sub_file(
    'lib/screens/equalizer_screen.dart',
    r"final live = active > 0 && eq\.isEnabled;",
    "final music = context.watch<MusicProvider>();\n"
    "                final live = eq.isEnabled &&\n"
    "                    (active > 0 ||\n"
    "                        music.isPlaying ||\n"
    "                        eq.hasHardwareEq ||\n"
    "                        (_liveStatus?['eqEnabled'] == true));",
    'eq live badge',
)

print('TOTAL', changed)
