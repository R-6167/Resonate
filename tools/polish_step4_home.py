#!/usr/bin/env python3
"""Step 4: glass polish for Home (For You) dashboard."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "lib/screens/home_screen.dart"
t = path.read_text()

if "ResonateGlassScaffold" in t and "resonate_glass.dart" in t:
    print("home: already polished")
    raise SystemExit(0)

if "resonate_glass.dart" not in t:
    t = t.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
        1,
    )

# Dashboard scaffold → glass
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
    raise SystemExit("home dashboard scaffold not found")
t = t.replace(old, new, 1)

# Recommendation empty states
t = t.replace(
    "return const [Card(child: ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Intelligence is off'), subtitle: Text('Your player remains fully manual. Enable it from Settings when you want local anticipation.')))];",
    "return const [ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Intelligence is off'), subtitle: Text('Your player remains fully manual. Enable it from Settings when you want local anticipation.')))];",
)
t = t.replace(
    "return const [Card(child: ListTile(leading: Icon(Icons.headphones_rounded), title: Text('Let Resonate get to know your taste'), subtitle: Text('Finishes, skips and song-to-song choices become local signals for future decisions.')))];",
    "return const [ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(leading: Icon(Icons.headphones_rounded), title: Text('Let Resonate get to know your taste'), subtitle: Text('Finishes, skips and song-to-song choices become local signals for future decisions.')))];",
)

# Continue listening card
old_cl = """        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.45),
          child: ListTile(
"""
new_cl = """        ResonateGlassCard(
          padding: EdgeInsets.zero,
          child: ListTile(
"""
if old_cl in t:
    t = t.replace(old_cl, new_cl, 1)
    print("continue listening → glass")
else:
    print("continue listening pattern skip")

# Now playing card
old_np = "        Card(child: ListTile(\n"
new_np = "        ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(\n"
if old_np in t:
    t = t.replace(old_np, new_np, 1)
    print("now playing → glass")
else:
    # try single-line
    t2 = t.replace(
        "Card(child: ListTile(\n          leading: CircleAvatar(child: Icon(music.isPlaying",
        "ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(\n          leading: CircleAvatar(child: Icon(music.isPlaying",
        1,
    )
    if t2 != t:
        t = t2
        print("now playing → glass (variant)")
    else:
        print("now playing pattern skip")

# _SessionCard
t = t.replace(
    "    return Card(\n",
    "    return ResonateGlassCard(\n      padding: EdgeInsets.zero,\n",
    1,
)

# _RecommendationTile Card
old_rt = None
for candidate in [
    "        return Card(\n",
    "        return Card(",
]:
    # only replace inside recommendation tile - look for nearby context
    pass

# Safer: replace the Card that wraps ListTile in recommendation after Consumer
if "class _RecommendationTileState" in t:
    chunk_start = t.find("class _RecommendationTileState")
    chunk = t[chunk_start:]
    if "return Card(" in chunk:
        # replace first return Card( in this class only
        abs_i = chunk_start + chunk.find("return Card(")
        # find end of "return Card(" line usage - replace opening
        # get a few chars
        snippet = t[abs_i : abs_i + 80]
        if "return Card(\n" in t[abs_i : abs_i + 20]:
            t = t[:abs_i] + "return ResonateGlassCard(\n          padding: EdgeInsets.zero," + t[abs_i + len("return Card(") :]
            print("recommendation tile → glass")
        elif snippet.startswith("return Card("):
            t = t[:abs_i] + "return ResonateGlassCard(padding: EdgeInsets.zero, " + t[abs_i + len("return Card(") :]
            print("recommendation tile → glass (inline)")

path.write_text(t)
print("home polished", path.stat().st_size)
