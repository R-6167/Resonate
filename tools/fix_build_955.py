#!/usr/bin/env python3
"""Fix build #955: library_management scaffold typo + about GlassCard args."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

lm = ROOT / "lib/screens/library_management_screen.dart"
t = lm.read_text()
# Broken: title: const Text('Library')),
old = "title: const Text('Library')),"
new = "title: const Text('Library'),"
if old in t:
    t = t.replace(old, new, 1)
    print("library_management: fixed title paren")
elif "title: const Text('Library')," in t:
    print("library_management: title already ok")
else:
    raise SystemExit("library_management title pattern not found")
lm.write_text(t)

about = ROOT / "lib/screens/about_screen.dart"
t = about.read_text()
# Broken _tile:
# return ResonateGlassCard(
#   padding: EdgeInsets.zero,
#   margin: const EdgeInsets.only(bottom: 12),
#   margin: const EdgeInsets.only(bottom: 12),
#   elevation: 0,
#   child: ExpansionTile(
old = """    return ResonateGlassCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 12),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: ExpansionTile(
"""
new = """    return ResonateGlassCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
"""
if old in t:
    t = t.replace(old, new, 1)
    print("about: fixed duplicate margin + elevation")
elif "elevation: 0," not in t:
    print("about: already clean")
else:
    # strip elevation only
    t2 = t.replace("      elevation: 0,\n", "")
    # dedupe margin lines if still doubled
    while (
        "margin: const EdgeInsets.only(bottom: 12),\n"
        "      margin: const EdgeInsets.only(bottom: 12),"
    ) in t2:
        t2 = t2.replace(
            "margin: const EdgeInsets.only(bottom: 12),\n"
            "      margin: const EdgeInsets.only(bottom: 12),",
            "margin: const EdgeInsets.only(bottom: 12),",
            1,
        )
    t = t2
    print("about: stripped elevation/deduped margin")
about.write_text(t)
print("done")
