#!/usr/bin/env python3
"""Precise resume v2 — match real MusicProvider symbols."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
music_path = ROOT / "lib/providers/music_provider.dart"
mode_path = ROOT / "lib/providers/mode_provider.dart"
player_path = ROOT / "lib/screens/player_screen.dart"

t = music_path.read_text()

if "_policyPreciseResume" not in t:
    t = t.replace(
        "  bool _policyShuffleAllowed = true;\n",
        "  bool _policyShuffleAllowed = true;\n  bool _policyPreciseResume = false;\n",
        1,
    )
    print("added _policyPreciseResume")

if "modePreciseResume" not in t:
    t = t.replace(
        "  bool get modeAllowsShuffle => _policyShuffleAllowed;\n",
        "  bool get modeAllowsShuffle => _policyShuffleAllowed;\n"
        "  bool get modePreciseResume => _policyPreciseResume;\n"
        "  int get _resumeMinMs => _policyPreciseResume ? 400 : 1500;\n"
        "  int get _resumeEndGuardMs => _policyPreciseResume ? 600 : 2000;\n"
        "  Duration get _resumePersistInterval =>\n"
        "      _policyPreciseResume ? const Duration(seconds: 1) : const Duration(seconds: 3);\n",
        1,
    )
    print("added getters")

# canContinueListening thresholds
t = t.replace(
    "if (_resumePositionMs < 1500) return false;",
    "if (_resumePositionMs < _resumeMinMs) return false;",
)
t = t.replace(
    "_resumePositionMs >= dur - 2000",
    "_resumePositionMs >= dur - _resumeEndGuardMs",
)

# applyModePlaybackPolicy
old = """  void applyModePlaybackPolicy({
    required bool crossfadeAllowed,
    required bool shuffleAllowed,
  }) {
    final changed = _policyCrossfadeAllowed != crossfadeAllowed ||
        _policyShuffleAllowed != shuffleAllowed;
    _policyCrossfadeAllowed = crossfadeAllowed;
    _policyShuffleAllowed = shuffleAllowed;
    if (changed) notifyListeners();
  }
"""
new = """  void applyModePlaybackPolicy({
    required bool crossfadeAllowed,
    required bool shuffleAllowed,
    bool preciseResume = false,
  }) {
    final changed = _policyCrossfadeAllowed != crossfadeAllowed ||
        _policyShuffleAllowed != shuffleAllowed ||
        _policyPreciseResume != preciseResume;
    _policyCrossfadeAllowed = crossfadeAllowed;
    _policyShuffleAllowed = shuffleAllowed;
    _policyPreciseResume = preciseResume;
    if (changed) notifyListeners();
  }
"""
if old in t:
    t = t.replace(old, new, 1)
    print("applyMode extended")
elif "preciseResume = false" in t:
    print("applyMode already has preciseResume")
else:
    print("WARNING applyMode miss")

# persist
t = t.replace(
    "now.difference(_lastResumePersist!) < const Duration(seconds: 3)",
    "now.difference(_lastResumePersist!) < _resumePersistInterval",
)
t = t.replace(
    "if (!force && position < 1500) return;",
    "if (!force && position < _resumeMinMs) return;",
)
t = t.replace(
    "if (cap > 0 && position >= cap - 2000) {",
    "if (cap > 0 && position >= cap - _resumeEndGuardMs) {",
)

# resumePositionFor and similar
t = t.replace("mapped != null && mapped > 1500", "mapped != null && mapped > _resumeMinMs")
t = t.replace(
    "_resumeSongId == currentSong!.id && _resumePositionMs > 1500",
    "_resumeSongId == currentSong!.id && _resumePositionMs > _resumeMinMs",
)
t = t.replace(
    "if (_resumeSongId == songId && _resumePositionMs > 1500) return _resumePositionMs;",
    "if (_resumeSongId == songId && _resumePositionMs > _resumeMinMs) return _resumePositionMs;",
)

# playSong resume logic
old_map = """    } else if (resumeIfPossible) {
      final mapped = resumePositionFor(song.id);
      if (mapped != null) {
        _resumeSongId = song.id;
        _resumePositionMs = mapped;
      }
    }
"""
new_map = """    } else if (resumeIfPossible || _policyPreciseResume) {
      final mapped = resumePositionFor(song.id);
      if (mapped != null) {
        _resumeSongId = song.id;
        _resumePositionMs = mapped;
      }
    }
"""
if old_map in t:
    t = t.replace(old_map, new_map, 1)
    print("playSong map")

t = t.replace(
    "resumeIfPossible && _resumeSongId == song.id && _resumePositionMs > 1500",
    "(resumeIfPossible || _policyPreciseResume) && _resumeSongId == song.id && _resumePositionMs > _resumeMinMs",
)
t = t.replace(
    "resumeIfPossible && _resumeSongId == song.id && _resumePositionMs > _resumeMinMs",
    "(resumeIfPossible || _policyPreciseResume) && _resumeSongId == song.id && _resumePositionMs > _resumeMinMs",
)

music_path.write_text(t)
print("music done")

# Mode push
mt = mode_path.read_text()
if "preciseResume:" not in mt:
    mt = mt.replace(
        "      crossfadeAllowed: p.crossfadeAllowed,\n"
        "      shuffleAllowed: p.shuffleAllowed,\n",
        "      crossfadeAllowed: p.crossfadeAllowed,\n"
        "      shuffleAllowed: p.shuffleAllowed,\n"
        "      preciseResume: p.preciseResume,\n",
        1,
    )
    mode_path.write_text(mt)
    print("mode push")
else:
    print("mode already pushes preciseResume")

# Player chip using canContinueListening
pt = player_path.read_text()
if "Episode position saved" not in pt:
    marker = "              GestureDetector(\n                onHorizontalDragEnd: (details) {\n"
    if marker in pt:
        hint = """              if (context.watch<ModeProvider>().policy.preciseResume &&
                  music.canContinueListening)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Align(
                    alignment: Alignment.center,
                    child: Chip(
                      avatar: const Icon(Icons.history_rounded, size: 18),
                      label: Text(
                        'Episode position saved · resumes from '
                        '${_fmtMs(music.resumePositionMs)}',
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                onHorizontalDragEnd: (details) {
"""
        pt = pt.replace(marker, hint, 1)
        if "String _fmtMs" not in pt:
            helper = """
  String _fmtMs(int ms) {
    final total = (ms / 1000).floor();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

"""
            if "  Future<void> _showMoreOptions" in pt:
                pt = pt.replace(
                    "  Future<void> _showMoreOptions",
                    helper + "  Future<void> _showMoreOptions",
                    1,
                )
            elif "  Future<void> _maybeShowSwipeTutorial" in pt:
                pt = pt.replace(
                    "  Future<void> _maybeShowSwipeTutorial",
                    helper + "  Future<void> _maybeShowSwipeTutorial",
                    1,
                )
        player_path.write_text(pt)
        print("player chip")
    else:
        print("player marker miss")
else:
    print("player chip already")

print("precise_resume_v2 complete")
