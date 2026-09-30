#!/usr/bin/env python3
"""Step 3: glass polish for Library family screens."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def ensure_import(t: str) -> str:
    if "resonate_glass.dart" in t:
        return t
    needle = "import 'package:flutter/material.dart';"
    if needle not in t:
        raise SystemExit("material import missing")
    return t.replace(needle, needle + "\nimport '../ui/resonate_glass.dart';", 1)


def scaffold_to_glass(t: str, title_literal: str | None = None) -> tuple[str, int]:
    """Convert Scaffold( appBar: AppBar( title: ..., actions?: ), body: ) to ResonateGlassScaffold.

    Returns (new_text, number_of_conversions).
    """
    count = 0
    out = []
    i = 0
    while True:
        m = re.search(r"\bScaffold\s*\(", t[i:])
        if not m:
            out.append(t[i:])
            break
        abs_start = i + m.start()
        # skip ScaffoldMessenger
        before = t[max(0, abs_start - 20) : abs_start]
        if before.endswith("ScaffoldMessenger.") or "ScaffoldMessenger" in before[-20:]:
            # actually ScaffoldMessenger.of — pattern is ScaffoldMessenger not Scaffold(
            pass
        # find matching paren for Scaffold(
        open_paren = i + m.end() - 1  # position of '('
        depth = 0
        j = open_paren
        while j < len(t):
            c = t[j]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        else:
            out.append(t[i:])
            break

        scaffold_src = t[abs_start : j + 1]  # Scaffold( ... )
        # Must look like a screen scaffold with appBar
        if "appBar:" not in scaffold_src or "body:" not in scaffold_src:
            out.append(t[i : j + 1])
            i = j + 1
            continue
        if "ScaffoldMessenger" in scaffold_src[:30]:
            out.append(t[i : j + 1])
            i = j + 1
            continue

        # Extract title widget from appBar
        title_m = re.search(
            r"appBar\s*:\s*AppBar\s*\([\s\S]*?title\s*:\s*([^,]+),",
            scaffold_src,
        )
        if not title_m:
            out.append(t[i : j + 1])
            i = j + 1
            continue

        title_expr = title_m.group(1).strip()

        # Extract actions if present inside AppBar
        actions_expr = None
        # Find AppBar( ... ) within scaffold
        ab = re.search(r"appBar\s*:\s*AppBar\s*\(", scaffold_src)
        if ab:
            ab_open = ab.end() - 1
            depth = 0
            k = ab_open
            while k < len(scaffold_src):
                c = scaffold_src[k]
                if c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            appbar_src = scaffold_src[ab.start() : k + 1]
            act = re.search(r"actions\s*:\s*\[", appbar_src)
            if act:
                # find matching ] for actions array — bracket depth
                a_open = act.end() - 1
                depth = 0
                p = a_open
                while p < len(appbar_src):
                    c = appbar_src[p]
                    if c == "[":
                        depth += 1
                    elif c == "]":
                        depth -= 1
                        if depth == 0:
                            break
                    p += 1
                actions_expr = appbar_src[act.start() : p + 1]  # actions: [ ... ]

        # Extract body expression
        body_m = re.search(r"body\s*:\s*", scaffold_src)
        if not body_m:
            out.append(t[i : j + 1])
            i = j + 1
            continue
        body_start = body_m.end()
        # body runs until the closing paren of Scaffold at depth 1 relative to scaffold content
        # scaffold_src is Scaffold( CONTENT )
        # content ends before last )
        content = scaffold_src[len("Scaffold(") : -1]
        body_rel = re.search(r"body\s*:\s*", content)
        body_expr = content[body_rel.end() :].rstrip()
        if body_expr.endswith(","):
            body_expr = body_expr[:-1].rstrip()

        parts = [
            "ResonateGlassScaffold(",
            f"      title: {title_expr},",
        ]
        if actions_expr:
            # re-indent actions line
            parts.append(f"      {actions_expr},")
        parts.append(f"      body: {body_expr},")
        parts.append("    )")
        replacement = "\n".join(parts)

        # preserve leading indentation of original Scaffold
        line_start = t.rfind("\n", 0, abs_start) + 1
        indent = t[line_start:abs_start]
        # If Scaffold was after => , indent may be empty on same line
        out.append(t[i:abs_start])
        out.append(replacement)
        count += 1
        i = j + 1

    return "".join(out), count


def polish_file(rel: str, soft_list_cards: bool = False) -> None:
    path = ROOT / rel
    t = path.read_text()
    if "ResonateGlassScaffold" in t and "Scaffold(" not in t.replace("ScaffoldMessenger", ""):
        print(f"{rel}: already glass")
        return
    t = ensure_import(t)
    t2, n = scaffold_to_glass(t)
    if n == 0:
        print(f"{rel}: no scaffold converted")
    else:
        print(f"{rel}: converted {n} scaffold(s)")

    # Section cards → glass (not every tiny Card)
    # Card(child: Padding( → glass
    t2 = t2.replace(
        "Card(child: Padding(",
        "ResonateGlassCard(padding: EdgeInsets.zero, child: Padding(",
    )
    t2 = t2.replace(
        "child: Card(\n",
        "child: ResonateGlassCard(\n                padding: EdgeInsets.zero,\n",
    )
    t2 = t2.replace(
        "] else Card(child: Padding(",
        "] else ResonateGlassCard(padding: EdgeInsets.zero, child: Padding(",
    )
    t2 = t2.replace(
        "Card(child: ListTile(",
        "ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(",
    )

    if soft_list_cards:
        # Dense rows: translucent Material card without BackdropFilter
        t2 = t2.replace(
            "return Card(child: ListTile(",
            (
                "return Card(\n"
                "          elevation: 0,\n"
                "          color: Theme.of(context).colorScheme.surface.withValues(\n"
                "            alpha: Theme.of(context).brightness == Brightness.dark ? 0.10 : 0.55,\n"
                "          ),\n"
                "          shape: RoundedRectangleBorder(\n"
                "            borderRadius: BorderRadius.circular(16),\n"
                "            side: BorderSide(\n"
                "              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),\n"
                "            ),\n"
                "          ),\n"
                "          child: ListTile("
            ),
        )
        # queue-style return Card(\n without child on same line — leave if already styled

    path.write_text(t2)


def main() -> None:
    polish_file("lib/screens/library_screen.dart")
    polish_file("lib/screens/playlists_screen.dart", soft_list_cards=True)
    polish_file("lib/screens/queue_screen.dart", soft_list_cards=True)
    polish_file("lib/screens/liked_songs_screen.dart")
    polish_file("lib/screens/listening_history_screen.dart")
    polish_file("lib/screens/library_management_screen.dart")
    print("step 3 done")


if __name__ == "__main__":
    main()
