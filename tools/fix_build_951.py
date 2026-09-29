#!/usr/bin/env python3
"""Fix build #951: missing playSong on MusicProvider + invalid EQ icon."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

# --- 1) Equalizer: valid Material icon ---
eq = ROOT / "lib/screens/equalizer_screen.dart"
if eq.exists():
    t = eq.read_text()
    t2 = t.replace("Icons.auto_fix_rounded", "Icons.palette_rounded")
    t2 = t2.replace("Icons.auto_awesome_rounded", "Icons.palette_rounded")
    if t2 != t:
        eq.write_text(t2)
        print("eq icon fixed")
    else:
        print("eq icon already ok or not present")
else:
    print("no equalizer_screen")

# --- 2) MusicProvider: ensure playSong + playQueueIndex exist ---
mp = ROOT / "lib/providers/music_provider.dart"
if not mp.exists():
    raise SystemExit("no music_provider")

t = mp.read_text()
has_play = "Future<bool> playSong(Song song" in t or "Future<void> playSong(Song" in t
has_qi = "Future<bool> playQueueIndex(int index)" in t or "Future<void> playQueueIndex(int" in t
print("has playSong", has_play, "has playQueueIndex", has_qi, "size", len(t))

if not has_play or not has_qi:
    # Inject thin public wrappers that call the internal player path if present,
    # otherwise implement minimal queue+play using existing fields.
    # Prefer calling an existing private/internal method.
    inject = '''
  // --- public playback API (restored for screens/widgets) ---
  Future<bool> playQueueIndex(int index) async {
    if (_queue.isEmpty) return false;
    final i = index.clamp(0, _queue.length - 1);
    _queueIndex = i;
    final song = _queue[i];
    try {
      if (_playSongInternal is Function) {
        // ignore: unnecessary_statements
      }
    } catch (_) {}
    try {
      return await _playSongInternal(song, queue: _queue, startIndex: i);
    } catch (_) {
      try {
        await play(song);
        return true;
      } catch (e) {
        debugPrint('playQueueIndex failed: $e');
        return false;
      }
    }
  }

  Future<bool> playSong(
    Song song, {
    List<Song>? queue,
    int startIndex = 0,
    bool resumeIfPossible = false,
    int? resumeAtMs,
  }) async {
    final q = queue ?? [song];
    final idx = startIndex.clamp(0, q.length - 1);
    _queue = List<Song>.from(q);
    _queueIndex = idx;
    try {
      return await _playSongInternal(
        q[idx],
        queue: q,
        startIndex: idx,
        resume: resumeIfPossible,
      );
    } catch (_) {
      try {
        await play(q[idx]);
        return true;
      } catch (e) {
        debugPrint('playSong failed: $e');
        return false;
      }
    }
  }
'''
    # Safer inject: only if we can find _playSongInternal or a play method
    has_internal = "_playSongInternal" in t
    has_play_method = re.search(r"\bFuture<.*> play\(", t) is not None or "Future<void> play(" in t

    if has_internal:
        inject = '''
  /// Public: play queue item at [index].
  Future<bool> playQueueIndex(int index) async {
    if (_queue.isEmpty) return false;
    final i = index.clamp(0, _queue.length - 1).toInt();
    return _playSongInternal(_queue[i], queue: _queue, startIndex: i);
  }

  /// Public: start [song], optionally with a full [queue].
  Future<bool> playSong(
    Song song, {
    List<Song>? queue,
    int startIndex = 0,
    bool resumeIfPossible = false,
    int? resumeAtMs,
  }) {
    return _playSongInternal(
      song,
      queue: queue,
      startIndex: startIndex,
      resume: resumeIfPossible,
    );
  }
'''
    else:
        # Minimal fallback using whatever player APIs exist
        inject = '''
  Future<bool> playQueueIndex(int index) async {
    if (_queue.isEmpty) return false;
    final i = index.clamp(0, _queue.length - 1).toInt();
    _queueIndex = i;
    notifyListeners();
    try {
      await _startPlayback(_queue[i]);
      return true;
    } catch (e) {
      debugPrint('playQueueIndex: $e');
      return false;
    }
  }

  Future<bool> playSong(
    Song song, {
    List<Song>? queue,
    int startIndex = 0,
    bool resumeIfPossible = false,
    int? resumeAtMs,
  }) async {
    final q = List<Song>.from(queue ?? [song]);
    final idx = startIndex.clamp(0, q.length - 1).toInt();
    _queue = q;
    _queueIndex = idx;
    notifyListeners();
    try {
      await _startPlayback(q[idx]);
      return true;
    } catch (e) {
      debugPrint('playSong: $e');
      return false;
    }
  }
'''

    # Insert before the last closing brace of the class MusicProvider
    # Find class MusicProvider and insert before final }
    # Simpler: insert before "void dispose()" if present, else before last }
    anchor = None
    for a in ["  @override\n  void dispose()", "  void dispose()", "  Future<void> dispose()"]:
        if a in t:
            anchor = a
            break
    if anchor:
        t = t.replace(anchor, inject + "\n" + anchor, 1)
    else:
        # before last top-level closing of file
        last = t.rfind("\n}")
        if last < 0:
            raise SystemExit("cannot find insert point")
        t = t[:last] + "\n" + inject + t[last:]

    mp.write_text(t)
    print("injected playSong/playQueueIndex, new size", len(t))
else:
    print("playSong already present — no inject")

print("done")
