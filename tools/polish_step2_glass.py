#!/usr/bin/env python3
"""Step 2: apply Resonate glass kit to settings-family screens."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def ensure_import(t: str) -> str:
    if "resonate_glass.dart" in t:
        return t
    if "import 'package:flutter/material.dart';" in t:
        return t.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/material.dart';\nimport '../ui/resonate_glass.dart';",
            1,
        )
    return t


def replace_cards(t: str) -> str:
    """Swap Material Card for glass card; keep inner padding."""
    # Prefer Card(child: → ResonateGlassCard(padding: EdgeInsets.zero, child:
    t = t.replace(
        "Card(\n                  child:",
        "ResonateGlassCard(\n                  padding: EdgeInsets.zero,\n                  margin: const EdgeInsets.only(bottom: 12),\n                  child:",
    )
    t = t.replace(
        "Card(\n                child:",
        "ResonateGlassCard(\n                padding: EdgeInsets.zero,\n                margin: const EdgeInsets.only(bottom: 12),\n                child:",
    )
    t = t.replace(
        "Card(\n              child:",
        "ResonateGlassCard(\n              padding: EdgeInsets.zero,\n              margin: const EdgeInsets.only(bottom: 12),\n              child:",
    )
    t = t.replace(
        "Card(\n            child:",
        "ResonateGlassCard(\n            padding: EdgeInsets.zero,\n            margin: const EdgeInsets.only(bottom: 12),\n            child:",
    )
    t = t.replace(
        "return Card(",
        "return ResonateGlassCard(\n      padding: EdgeInsets.zero,\n      margin: const EdgeInsets.only(bottom: 12),",
    )
    return t


def polish_crossfade(path: Path) -> None:
    t = path.read_text()
    if "ResonateGlassScaffold" in t and "Crossfade" in t:
        print("crossfade: already glass")
        return
    t = ensure_import(t)
    old = '''    return Scaffold(
      appBar: AppBar(
        title: const Text('Crossfade'),
        actions: [
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: Consumer<CrossfadeProvider>('''
    new = '''    return ResonateGlassScaffold(
      title: const Text('Crossfade'),
      actions: [
        IconButton(
          tooltip: 'Reset',
          icon: const Icon(Icons.restart_alt_rounded),
          onPressed: () => _confirmReset(context),
        ),
      ],
      body: Consumer<CrossfadeProvider>('''
    if old not in t:
        raise SystemExit("crossfade scaffold not found")
    t = t.replace(old, new, 1)
    t = replace_cards(t)
    path.write_text(t)
    print("crossfade polished")


def polish_dj(path: Path) -> None:
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("dj: already glass")
        return
    t = ensure_import(t)
    old = '''    return Scaffold(
      appBar: AppBar(title: const Text('DJ Mode')),
      body: Consumer<DjModeProvider>('''
    new = '''    return ResonateGlassScaffold(
      title: const Text('DJ Mode'),
      body: Consumer<DjModeProvider>('''
    if old not in t:
        raise SystemExit("dj scaffold not found")
    t = t.replace(old, new, 1)
    t = replace_cards(t)
    path.write_text(t)
    print("dj polished")


def polish_intelligence(path: Path) -> None:
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("intelligence: already glass")
        return
    t = ensure_import(t)
    old = '''    return Scaffold(
      appBar: AppBar(title: const Text('Resonate Intelligence')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Consumer<IntelligenceProvider>(builder: (context, intelligence, _) => ListView(padding: const EdgeInsets.only(bottom: 36), children: ['''
    new = '''    return ResonateGlassScaffold(
      title: const Text('Resonate Intelligence'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<IntelligenceProvider>(builder: (context, intelligence, _) => ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 36), children: ['''
    if old not in t:
        # try multiline variant
        raise SystemExit("intelligence scaffold not found")
    t = t.replace(old, new, 1)
    t = replace_cards(t)
    path.write_text(t)
    print("intelligence polished")


def polish_diagnostics(path: Path) -> None:
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("diagnostics: already glass")
        return
    t = ensure_import(t)
    old = '''    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Diagnostics')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 36),
              children: ['''
    new = '''    return ResonateGlassScaffold(
      title: const Text('Privacy & Diagnostics'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 36),
              children: ['''
    if old not in t:
        raise SystemExit("diagnostics scaffold not found")
    t = t.replace(old, new, 1)
    t = replace_cards(t)
    path.write_text(t)
    print("diagnostics polished")


def polish_about(path: Path) -> None:
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("about: already glass")
        return
    t = ensure_import(t)
    old = '''    return Scaffold(
      appBar: AppBar(title: const Text('About Resonate')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: ['''
    new = '''    return ResonateGlassScaffold(
      title: const Text('About Resonate'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: ['''
    if old not in t:
        raise SystemExit("about scaffold not found")
    t = t.replace(old, new, 1)
    t = replace_cards(t)
    path.write_text(t)
    print("about polished")


def main() -> None:
    polish_crossfade(ROOT / "lib/screens/crossfade_screen.dart")
    polish_dj(ROOT / "lib/screens/dj_mode_settings_screen.dart")
    polish_intelligence(ROOT / "lib/screens/intelligence_settings_screen.dart")
    polish_diagnostics(ROOT / "lib/screens/diagnostics_screen.dart")
    polish_about(ROOT / "lib/screens/about_screen.dart")
    print("step 2 done")


if __name__ == "__main__":
    main()
