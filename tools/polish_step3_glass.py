#!/usr/bin/env python3
"""Step 3: glass polish for Library, Playlists, Queue, Liked, History, Library management."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def ensure_import(t: str) -> str:
    if "resonate_glass.dart" in t:
        return t
    needle = "import 'package:flutter/material.dart';"
    if needle not in t:
        raise SystemExit("material import missing")
    return t.replace(
        needle,
        needle + "\nimport '../ui/resonate_glass.dart';",
        1,
    )


def soft_list_card(t: str) -> str:
    """Dense list rows: translucent card without BackdropFilter cost."""
    # Only rewrite simple Card(child: ListTile patterns later if needed.
    return t


def polish_library() -> None:
    path = ROOT / "lib/screens/library_screen.dart"
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("library: already")
        return
    t = ensure_import(t)
    # Find return Scaffold( ... body:
    start = t.find("    return Scaffold(\n      appBar: AppBar(\n        title: const Text('Library'),")
    if start < 0:
        raise SystemExit("library scaffold start not found")
    # Replace through body: with glass scaffold; keep actions inside by parsing carefully.
    # Extract actions block
    actions_start = t.find("actions: [", start)
    # Find matching body:
    body_idx = t.find("\n      body:", start)
    if body_idx < 0:
        raise SystemExit("library body not found")
    # From start to body_idx is scaffold+appbar; rebuild as glass
    head = t[:start]
    rest = t[body_idx:]  # starts with \n      body:
    # Extract actions content between actions: [ and closing of appBar
    # Simpler: string replace known prefix
    old_prefix = t[start:body_idx]
    # Build new prefix from old by converting AppBar fields
    if "title: const Text('Library')" not in old_prefix:
        raise SystemExit("library title missing")
    # actions from old_prefix
    a0 = old_prefix.find("actions: [")
    if a0 < 0:
        raise SystemExit("library actions missing")
    # find end of actions array — last ], before closing of AppBar
    # old_prefix ends before body, includes AppBar close
    actions_block = old_prefix[a0:]
    # strip trailing appbar close noise: actions: [ ... ],\n      ),
    # find the ], that closes actions — then ), closes AppBar
    # Use everything from actions: [ to the line before final ), of AppBar
    new_prefix = (
        "    return ResonateGlassScaffold(\n"
        "      title: const Text('Library'),\n"
        "      " + actions_block.rstrip()
    )
    # actions_block may end with ")," for AppBar — clean
    # Typical end: "      )," after actions
    if new_prefix.rstrip().endswith("),"):
        # remove AppBar closing
        new_prefix = new_prefix.rstrip()
        # remove trailing ),
        if new_prefix.endswith("),"):
            new_prefix = new_prefix[:-2].rstrip()
            if new_prefix.endswith(","):
                pass  # actions ends with ],
            new_prefix += "\n"
    t = head + new_prefix + rest
    # body: Column stays; wrap search Card at top
    t = t.replace(
        "child: Card(\n",
        "child: ResonateGlassCard(\n                padding: EdgeInsets.zero,\n",
        1,
    )
    path.write_text(t)
    print("library polished")


def polish_playlists() -> None:
    path = ROOT / "lib/screens/playlists_screen.dart"
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("playlists: already")
        return
    t = ensure_import(t)
    old = """  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Playlists'), actions: [
      Consumer<PlaylistProvider>(builder: (_, provider, __) => IconButton(tooltip: 'Refresh smart playlists', onPressed: provider.isSmartRefreshing ? null : () => _refreshSmart(context), icon: provider.isSmartRefreshing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded))),
      IconButton(onPressed: () => _create(context), icon: const Icon(Icons.add_rounded), tooltip: 'Create playlist'),
    ]),
    body: Consumer<PlaylistProvider>(builder: (context, provider, _) {
"""
    new = """  Widget build(BuildContext context) => ResonateGlassScaffold(
    title: const Text('Playlists'),
    actions: [
      Consumer<PlaylistProvider>(builder: (_, provider, __) => IconButton(tooltip: 'Refresh smart playlists', onPressed: provider.isSmartRefreshing ? null : () => _refreshSmart(context), icon: provider.isSmartRefreshing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded))),
      IconButton(onPressed: () => _create(context), icon: const Icon(Icons.add_rounded), tooltip: 'Create playlist'),
    ],
    body: Consumer<PlaylistProvider>(builder: (context, provider, _) {
"""
    if old not in t:
        raise SystemExit("playlists scaffold not found")
    t = t.replace(old, new, 1)
    # List item cards → soft translucent (avoid per-row blur)
    t = t.replace(
        "return Card(child: ListTile(",
        "return Card(\n          elevation: 0,\n          color: Theme.of(context).colorScheme.surface.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.10 : 0.55),\n          shape: RoundedRectangleBorder(\n            borderRadius: BorderRadius.circular(16),\n            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35)),\n          ),\n          child: ListTile(",
    )
    # Playlist detail scaffold
    old2 = """    appBar: AppBar(title: Text(widget.playlist.name), actions: [IconButton(onPressed: _addSongs, icon: const Icon(Icons.playlist_add_rounded))],),
    body: FutureBuilder<List<Song>>(future: _songs, builder: (context, snapshot) {
"""
    # Detail is still Scaffold( — convert whole if present
    if "class PlaylistDetailScreen" in t and "ResonateGlassScaffold" not in t[t.find("class PlaylistDetailScreen"):
        # only main was converted; detail still Scaffold
        pass
    # Convert PlaylistDetailScreen scaffold
    detail_old = None
    marker = "class _PlaylistDetailScreenState"
    if marker in t:
        chunk = t[t.find(marker):]
        if "Scaffold(" in chunk and "ResonateGlassScaffold" not in chunk:
            # find build method scaffold
            old_d = """  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.playlist.name), actions: [IconButton(onPressed: _addSongs, icon: const Icon(Icons.playlist_add_rounded))],),
    body: FutureBuilder<List<Song>>(future: _songs, builder: (context, snapshot) {
"""
            new_d = """  Widget build(BuildContext context) => ResonateGlassScaffold(
    title: Text(widget.playlist.name),
    actions: [IconButton(onPressed: _addSongs, icon: const Icon(Icons.playlist_add_rounded))],
    body: FutureBuilder<List<Song>>(future: _songs, builder: (context, snapshot) {
"""
            if old_d in t:
                t = t.replace(old_d, new_d, 1)
                print("playlist detail polished")
            else:
                print("playlist detail pattern skip")
    path.write_text(t)
    print("playlists polished")


def polish_queue() -> None:
    path = ROOT / "lib/screens/queue_screen.dart"
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("queue: already")
        return
    t = ensure_import(t)
    start = t.find("    return Scaffold(\n      appBar: AppBar(\n        title: const Text('Queue'),")
    if start < 0:
        raise SystemExit("queue scaffold not found")
    body_idx = t.find("\n      body:", start)
    old_prefix = t[start:body_idx]
    a0 = old_prefix.find("actions: [")
    if a0 < 0:
        raise SystemExit("queue actions missing")
    actions_block = old_prefix[a0:].rstrip()
    if actions_block.endswith("),"):
        actions_block = actions_block[:-2].rstrip()
    new_prefix = (
        "    return ResonateGlassScaffold(\n"
        "      title: const Text('Queue'),\n"
        "      " + actions_block + "\n"
    )
    t = t[:start] + new_prefix + t[body_idx:]
    # list item Card
    t = t.replace(
        "return Card(",
        "return Card(\n                      elevation: 0,\n                      color: Theme.of(context).colorScheme.surface.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.10 : 0.55),\n                      shape: RoundedRectangleBorder(\n                        borderRadius: BorderRadius.circular(14),\n                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35)),\n                      ),",
        1,
    )
    path.write_text(t)
    print("queue polished")


def polish_liked() -> None:
    path = ROOT / "lib/screens/liked_songs_screen.dart"
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("liked: already")
        return
    t = ensure_import(t)
    start = t.find("    return Scaffold(\n      appBar: AppBar(\n        title: const Text('Liked Songs'),")
    if start < 0:
        raise SystemExit("liked scaffold not found")
    body_idx = t.find("\n      body:", start)
    old_prefix = t[start:body_idx]
    a0 = old_prefix.find("actions: [")
    if a0 < 0:
        raise SystemExit("liked actions missing")
    actions_block = old_prefix[a0:].rstrip()
    if actions_block.endswith("),"):
        actions_block = actions_block[:-2].rstrip()
    new_prefix = (
        "    return ResonateGlassScaffold(\n"
        "      title: const Text('Liked Songs'),\n"
        "      " + actions_block + "\n"
    )
    t = t[:start] + new_prefix + t[body_idx:]
    path.write_text(t)
    print("liked polished")


def polish_history() -> None:
    path = ROOT / "lib/screens/listening_history_screen.dart"
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("history: already")
        return
    t = ensure_import(t)
    # uses Scaffold( without return maybe
    old = None
    for candidate in [
        """  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Listening History'),
""",
        """  Widget build(BuildContext context) {
    return Scaffold(
    appBar: AppBar(
      title: const Text('Listening History'),
""",
    ]:
        if candidate in t:
            old = candidate
            break
    if old is None:
        # looser
        idx = t.find("title: const Text('Listening History')")
        if idx < 0:
            raise SystemExit("history title not found")
        # find Scaffold before it
        sc = t.rfind("Scaffold(", 0, idx)
        print("history context:", repr(t[sc-40:sc+200]))
        raise SystemExit("history scaffold pattern not found")

    # Extract full appBar through body
    start = t.find(old)
    body_idx = t.find("body:", start)
    if body_idx < 0:
        raise SystemExit("history body not found")
    # include leading whitespace for body line
    body_line_start = t.rfind("\n", 0, body_idx) + 1
    prefix = t[start:body_line_start]
    # actions from prefix
    a0 = prefix.find("actions: [")
    if a0 < 0:
        new_prefix = "  Widget build(BuildContext context) => ResonateGlassScaffold(\n    title: const Text('Listening History'),\n    "
    else:
        actions_block = prefix[a0:].rstrip()
        # strip AppBar closing
        while actions_block.endswith(")") or actions_block.endswith(","):
            if actions_block.endswith("),"):
                actions_block = actions_block[:-2].rstrip()
                break
            if actions_block.endswith(")"):
                actions_block = actions_block[:-1].rstrip()
                continue
            break
        new_prefix = (
            "  Widget build(BuildContext context) => ResonateGlassScaffold(\n"
            "    title: const Text('Listening History'),\n"
            "    " + actions_block + "\n"
        )
    t = t[:start] + new_prefix + t[body_line_start:]
    t = t.replace(
        "Card(child: Padding(padding: const EdgeInsets.all(16),",
        "ResonateGlassCard(padding: const EdgeInsets.all(16),",
        1,
    )
    path.write_text(t)
    print("history polished")


def polish_lib_mgmt() -> None:
    path = ROOT / "lib/screens/library_management_screen.dart"
    t = path.read_text()
    if "ResonateGlassScaffold" in t:
        print("lib mgmt: already")
        return
    t = ensure_import(t)
    old = """    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
"""
    new = """    return ResonateGlassScaffold(
      title: const Text('Library'),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 28), children: [
"""
    if old not in t:
        raise SystemExit("lib mgmt scaffold not found")
    t = t.replace(old, new, 1)
    # Cards → glass
    t = t.replace(
        "Card(child: Padding(",
        "ResonateGlassCard(padding: EdgeInsets.zero, child: Padding(",
    )
    t = t.replace(
        "Card(\n",
        "ResonateGlassCard(\n          padding: EdgeInsets.zero,\n",
    )
    t = t.replace(
        "Card(child: ListTile(",
        "ResonateGlassCard(padding: EdgeInsets.zero, child: ListTile(",
    )
    t = t.replace(
        "] else Card(child: Padding(",
        "] else ResonateGlassCard(padding: EdgeInsets.zero, child: Padding(",
    )
    path.write_text(t)
    print("lib mgmt polished")


def main() -> None:
    polish_library()
    polish_playlists()
    polish_queue()
    polish_liked()
    polish_history()
    polish_lib_mgmt()
    print("step 3 done")


if __name__ == "__main__":
    main()
