#!/usr/bin/env python3
"""Step 4: glass polish for complete Home / For You dashboard."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "lib/screens/home_screen.dart"
t = path.read_text()

if "ResonateGlassScaffold" in t and "class _RecommendationTileState" in t:
    print("home already complete+glass", len(t))
    raise SystemExit(0)

if "class _RecommendationTileState" not in t:
    raise SystemExit("home truncated — restore classes first")

if "resonate_glass.dart" not in t:
    t = t.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
        1,
    )

old = """    return Scaffold(
      appBar: AppBar(title: const ResonateLogo(size: 48)),
      body: RefreshIndicator(
        onRefresh: intelligence.refreshRecommendations,
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 34), children: children),
      ),
    );"""
new = """    return ResonateGlassScaffold(
      title: const ResonateLogo(size: 48),
      body: RefreshIndicator(
        onRefresh: intelligence.refreshRecommendations,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 34), children: children),
      ),
    );"""
if old not in t:
    raise SystemExit("dashboard scaffold not found")
t = t.replace(old, new, 1)

t = t.replace(
    "return const [Card(child: ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Intelligence is off'), subtitle: Text('Your player remains fully manual. Enable it from Settings when you want local anticipation.')))];",
    "return const [ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Intelligence is off'), subtitle: Text('Your player remains fully manual. Enable it from Settings when you want local anticipation.')))];",
)
t = t.replace(
    "return const [Card(child: ListTile(leading: Icon(Icons.headphones_rounded), title: Text('Let Resonate get to know your taste'), subtitle: Text('Finishes, skips and song-to-song choices become local signals for future decisions.')))];",
    "return const [ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(leading: Icon(Icons.headphones_rounded), title: Text('Let Resonate get to know your taste'), subtitle: Text('Finishes, skips and song-to-song choices become local signals for future decisions.')))];",
)

old_cl = """        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.45),
          child: ListTile(
"""
new_cl = """        ResonateGlassCard(
          padding: EdgeInsets.zero,
          child: ListTile(
"""
if old_cl not in t:
    raise SystemExit("continue listening card not found")
t = t.replace(old_cl, new_cl, 1)

old_np = "        Card(child: ListTile(\n          leading: CircleAvatar(child: Icon(music.isPlaying"
new_np = "        ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(\n          leading: CircleAvatar(child: Icon(music.isPlaying"
if old_np not in t:
    raise SystemExit("now playing card not found")
t = t.replace(old_np, new_np, 1)

idx = t.find("class _SessionCard")
if idx < 0:
    raise SystemExit("SessionCard missing")
abs_i = idx + t[idx:].find("return Card(")
if abs_i < idx:
    raise SystemExit("SessionCard return Card missing")
t = t[:abs_i] + "return ResonateGlassCard(\n      padding: EdgeInsets.zero," + t[abs_i + len("return Card(") :]

idx = t.find("class _RecommendationTileState")
if idx < 0:
    raise SystemExit("RecommendationTile missing")
abs_i = idx + t[idx:].find("return Card(")
if abs_i < idx:
    raise SystemExit("RecommendationTile return Card missing")
t = t[:abs_i] + "return ResonateGlassCard(\n          padding: EdgeInsets.zero," + t[abs_i + len("return Card(") :]

assert "ResonateGlassScaffold" in t
assert "class _RecommendationTileState" in t
path.write_text(t)
print("home glass polished", len(t), "glass markers", t.count("ResonateGlass"))
