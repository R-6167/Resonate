#!/usr/bin/env python3
"""Step 5: glass Player + remove duplicate Audio effects under More."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "lib/screens/player_screen.dart"
t = path.read_text()

# --- Remove duplicate Audio effects under More ---
if "title: const Text('Audio effects')" in t:
    # Drop provider read if only used for that tile
    t = t.replace(
        "    final effects = context.read<AudioEffectsProvider>();\n\n",
        "",
        1,
    )
    # Remove the full ListTile block for Audio effects
    old_tile = '''              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded),
                title: const Text('Audio effects'),
                subtitle: Text(
                  effects.effectsEnabled
                      ? 'Bass, width, reverb and loudness'
                      : 'Disabled',
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AudioEffectsScreen(),
                    ),
                  );
                },
              ),
'''
    if old_tile not in t:
        raise SystemExit("Audio effects ListTile not found")
    t = t.replace(old_tile, "", 1)
    print("removed Audio effects from More")
else:
    print("Audio effects tile already gone")

# Drop unused imports
if "audio_effects_provider.dart" in t and "AudioEffectsProvider" not in t:
    t = t.replace("import '../providers/audio_effects_provider.dart';\n", "")
    print("dropped audio_effects_provider import")
if "audio_effects_screen.dart" in t and "AudioEffectsScreen" not in t:
    t = t.replace("import 'audio_effects_screen.dart';\n", "")
    print("dropped audio_effects_screen import")

# --- Glass kit ---
if "resonate_glass.dart" not in t:
    t = t.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
        1,
    )

if "ResonateGlassScaffold" not in t:
    # Convert main Scaffold with AppBar to glass, keep actions
    start = t.find("    return Scaffold(\n      appBar: AppBar(\n        title: const Text('Now Playing'),")
    if start < 0:
        raise SystemExit("player scaffold not found")
    body_idx = t.find("\n      body:", start)
    if body_idx < 0:
        raise SystemExit("player body not found")
    old_prefix = t[start:body_idx]
    a0 = old_prefix.find("actions: [")
    if a0 < 0:
        raise SystemExit("player actions missing")
    actions_block = old_prefix[a0:].rstrip()
    if actions_block.endswith("),"):
        actions_block = actions_block[:-2].rstrip()
    new_prefix = (
        "    return ResonateGlassScaffold(\n"
        "      title: const Text('Now Playing'),\n"
        "      " + actions_block + "\n"
    )
    t = t[:start] + new_prefix + t[body_idx:]
    print("player scaffold → glass")
else:
    print("player scaffold already glass")

# Transport / tool strip Card → glass
old_card = """              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
"""
new_card = """              ResonateGlassCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
"""
if old_card in t:
    t = t.replace(old_card, new_card, 1)
    print("transport card → glass")

# _NextCard
if "class _NextCard" in t:
    idx = t.find("class _NextCard")
    # first return Card( after class
    rel = t[idx:].find("return Card(")
    if rel >= 0:
        abs_i = idx + rel
        t = (
            t[:abs_i]
            + "return ResonateGlassCard(\n      padding: EdgeInsets.zero,"
            + t[abs_i + len("return Card(") :]
        )
        print("next card → glass")

path.write_text(t)
print("player polished", path.stat().st_size)
