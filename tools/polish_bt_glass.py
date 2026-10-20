#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "lib/screens/settings_screen.dart"
t = path.read_text()
if "resonate_glass.dart" not in t:
    t = t.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
        1,
    )
old = """  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bluetooth & media controls')),
        body: Consumer<BluetoothProvider>(
"""
new = """  Widget build(BuildContext context) => ResonateGlassScaffold(
        title: const Text('Bluetooth & media controls'),
        body: Consumer<BluetoothProvider>(
"""
if old in t:
    t = t.replace(old, new, 1)
    print("BT → glass")
elif "BluetoothSettingsScreen" in t and "ResonateGlassScaffold" in t:
    print("BT already glass-ish")
else:
    raise SystemExit("BT pattern not found")
# First Card in BT body → glass if still plain
# only touch the first Card after BluetoothSettingsScreen
idx = t.find("class BluetoothSettingsScreen")
if idx >= 0:
    rest = t[idx:]
    rest2 = rest.replace(
        "Card(\n                child: Padding(\n                  padding: const EdgeInsets.all(18),",
        "ResonateGlassCard(\n                child: Padding(\n                  padding: const EdgeInsets.all(18),",
        1,
    )
    t = t[:idx] + rest2
    print("BT intro card → glass")
path.write_text(t)
