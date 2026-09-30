#!/usr/bin/env python3
"""Rewrite SettingsScreen shell to use Resonate glass kit (keep all routes/actions)."""
from pathlib import Path

p = Path("lib/screens/settings_screen.dart")
t = p.read_text()

if "resonate_glass.dart" in t and "ResonateGlassScaffold" in t:
    print("settings already polished")
    raise SystemExit(0)

# Inject import
if "resonate_glass.dart" not in t:
    t = t.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
        1,
    )

# Replace Scaffold shell for SettingsScreen only (first occurrence of the main build)
old_build = '''  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: ['''

new_build = '''  @override
  Widget build(BuildContext context) => ResonateGlassScaffold(
        title: const Text('Settings'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: ['''

if old_build not in t:
    # try alternate spacing
    old_build = old_build.replace(" => Scaffold(", "=> Scaffold(")
if old_build not in t:
    raise SystemExit("SettingsScreen build scaffold not found")
t = t.replace(old_build, new_build, 1)

# Replace _section helper
old_section = '''  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children, {bool initiallyExpanded = false}) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(title),
          children: children,
        ),
      );'''

new_section = '''  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children, {bool initiallyExpanded = false}) =>
      ResonateGlassSection(
        title: title,
        icon: icon,
        initiallyExpanded: initiallyExpanded,
        children: children,
      );'''

if old_section not in t:
    raise SystemExit("_section helper not found")
t = t.replace(old_section, new_section, 1)

# Replace _item helper
old_item = '''  Widget _item(BuildContext context, String title, String subtitle, IconData icon, Widget screen) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      );'''

new_item = '''  Widget _item(BuildContext context, String title, String subtitle, IconData icon, Widget screen) =>
      ResonateGlassTile(
        title: title,
        subtitle: subtitle,
        icon: icon,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      );'''

if old_item not in t:
    raise SystemExit("_item helper not found")
t = t.replace(old_item, new_item, 1)

# Replace _confirmItem
old_confirm = '''  Widget _confirmItem(BuildContext context, String title, String subtitle, IconData icon, String text, IconData trailingIcon, Future<void> Function() action) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(trailingIcon),
        onTap: () => _confirm(context, title, text, action),
      );'''

new_confirm = '''  Widget _confirmItem(BuildContext context, String title, String subtitle, IconData icon, String text, IconData trailingIcon, Future<void> Function() action) =>
      ResonateGlassTile(
        title: title,
        subtitle: subtitle,
        icon: icon,
        trailing: Icon(trailingIcon),
        onTap: () => _confirm(context, title, text, action),
      );'''

if old_confirm not in t:
    raise SystemExit("_confirmItem helper not found")
t = t.replace(old_confirm, new_confirm, 1)

# Top profile/theme cards: wrap plain Card in glass if still Card( at top of list
# Leave Consumer cards — only restyle via section helpers is enough for step 1.

p.write_text(t)
print("settings polished", p.stat().st_size)
