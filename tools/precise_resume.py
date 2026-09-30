#!/usr/bin/env python3
"""Enforce PlaybackPolicy.preciseResume in MusicProvider + ModeProvider push."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_music() -> None:
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()
    if "_policyPreciseResume" in t and "_resumeMinMs" in t:
        print("music: precise resume already present")
        return

    # Policy flag next to other policy flags
    if "bool _policyShuffleAllowed = true;" in t and "_policyPreciseResume" not in t:
        t = t.replace(
            "  bool _policyShuffleAllowed = true;\n",
            "  bool _policyShuffleAllowed = true;\n"
            "  bool _policyPreciseResume = false;\n",
            1,
        )

    # Thresholds helpers after policy fields / near canResume
    if "int get _resumeMinMs" not in t:
        # Insert after modeAllowsShuffle getter if present, else after policy flags
        anchor = "  bool get modeAllowsShuffle => _policyShuffleAllowed;\n"
        helpers = (
            "  bool get modeAllowsShuffle => _policyShuffleAllowed;\n"
            "  bool get modePreciseResume => _policyPreciseResume;\n"
            "\n"
            "  /// Minimum saved position to treat as resumable.\n"
            "  int get _resumeMinMs => _policyPreciseResume ? 400 : 1500;\n"
            "\n"
            "  /// Within this many ms of duration end → treat as finished.\n"
            "  int get _resumeEndGuardMs => _policyPreciseResume ? 600 : 2000;\n"
            "\n"
            "  Duration get _resumePersistInterval =>\n"
            "      _policyPreciseResume ? const Duration(seconds: 1) : const Duration(seconds: 3);\n"
        )
        if anchor in t:
            t = t.replace(anchor, helpers, 1)
        else:
            print("music: modeAllowsShuffle anchor miss — injecting after policy flags")
            t = t.replace(
                "  bool _policyPreciseResume = false;\n",
                "  bool _policyPreciseResume = false;\n"
                "  bool get modePreciseResume => _policyPreciseResume;\n"
                "  int get _resumeMinMs => _policyPreciseResume ? 400 : 1500;\n"
                "  int get _resumeEndGuardMs => _policyPreciseResume ? 600 : 2000;\n"
                "  Duration get _resumePersistInterval =>\n"
                "      _policyPreciseResume ? const Duration(seconds: 1) : const Duration(seconds: 3);\n",
                1,
            )

    # canResumeCurrentQueueSong thresholds
    old_can = """    if (_resumeSongId != song.id) return false;
    if (_resumePositionMs < 1500) return false;
"""
    # may have duration line after
    if "_resumePositionMs < 1500" in t:
        t = t.replace("_resumePositionMs < 1500", "_resumePositionMs < _resumeMinMs")
        print("music: canResume min threshold")
    if "_resumePositionMs >= dur - 2000" in t:
        t = t.replace(
            "_resumePositionMs >= dur - 2000",
            "_resumePositionMs >= dur - _resumeEndGuardMs",
        )
        print("music: canResume end guard")

    # applyModePlaybackPolicy extended
    old_apply = """  void applyModePlaybackPolicy({
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
    new_apply = """  void applyModePlaybackPolicy({
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
    if old_apply in t:
        t = t.replace(old_apply, new_apply, 1)
        print("music: applyModePlaybackPolicy + preciseResume")
    else:
        print("music: applyModePlaybackPolicy block miss")

    # _persistResumePosition: interval + thresholds
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
    print("music: persist thresholds")

    # resumePositionFor
    if "mapped > 1500" in t:
        t = t.replace("mapped > 1500", "mapped > _resumeMinMs")

    # Other 1500 checks for resume restore after init
    t = t.replace(
        "_resumeSongId == currentSong!.id && _resumePositionMs > 1500",
        "_resumeSongId == currentSong!.id && _resumePositionMs > _resumeMinMs",
    )
    t = t.replace(
        "if (_resumeSongId == songId && _resumePositionMs > 1500) return _resumePositionMs;",
        "if (_resumeSongId == songId && _resumePositionMs > _resumeMinMs) return _resumePositionMs;",
    )

    # playSong: auto resumeIfPossible under precise policy
    old_play = "  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0, bool resumeIfPossible = false, int? resumeAtMs}) async {"
    # might not have async on same line
    if "bool resumeIfPossible = false" in t and "preciseResume default" not in t:
        # Find playSong body start and inject after signature block
        # Look for the function and inject early logic
        marker = "  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0, bool resumeIfPossible = false, int? resumeAtMs})"
        if marker not in t:
            print("music: playSong signature miss")
        else:
            # After opening of function - find first lines inside
            # Common: _clearDjStretch or similar after intent
            # Inject right after method starts - search for typical first line
            # safer: replace the shouldResume computation and the resumeIfPossible handling
            old_should = (
                "    final shouldResume = resumeIfPossible && _resumeSongId == song.id && _resumePositionMs > 1500;\n"
            )
            new_should = (
                "    // Podcast/Audiobook policy: always try mid-episode resume unless an explicit resumeAtMs was passed as 0-start later.\n"
                "    final effectiveResume = resumeIfPossible || _policyPreciseResume;\n"
                "    final shouldResume = effectiveResume && _resumeSongId == song.id && _resumePositionMs > _resumeMinMs;\n"
            )
            if old_should in t:
                t = t.replace(old_should, new_should, 1)
                print("music: playSong shouldResume precise")
            else:
                # try without spaces
                if "_resumePositionMs > 1500" in t:
                    # replace remaining critical play path
                    t = t.replace(
                        "resumeIfPossible && _resumeSongId == song.id && _resumePositionMs > 1500",
                        "(resumeIfPossible || _policyPreciseResume) && _resumeSongId == song.id && _resumePositionMs > _resumeMinMs",
                    )
                    print("music: playSong shouldResume alt")

            # Also when resumeIfPossible loads from map, use precise auto
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
                print("music: playSong map load precise")

    path.write_text(t)
    print("music precise resume patched")


def patch_mode() -> None:
    path = ROOT / "lib/providers/mode_provider.dart"
    t = path.read_text()
    if "preciseResume:" in t:
        print("mode: preciseResume already pushed")
        return
    old = """    _music?.applyModePlaybackPolicy(
      crossfadeAllowed: p.crossfadeAllowed,
      shuffleAllowed: p.shuffleAllowed,
    );
"""
    new = """    _music?.applyModePlaybackPolicy(
      crossfadeAllowed: p.crossfadeAllowed,
      shuffleAllowed: p.shuffleAllowed,
      preciseResume: p.preciseResume,
    );
"""
    if old not in t:
        raise SystemExit("mode: push policy block miss")
    t = t.replace(old, new, 1)
    path.write_text(t)
    print("mode: preciseResume pushed")


def patch_player_hint() -> None:
    """Optional: show resume position chip when precise mode + can resume."""
    path = ROOT / "lib/screens/player_screen.dart"
    t = path.read_text()
    if "modePreciseResume" in t or "Resuming from" in t:
        print("player: resume hint already")
        return

    # Insert a small chip under title area is hard without exact markers.
    # Add after ListView banner / before art if we can find GestureDetector for art.
    marker = "              GestureDetector(\n                onHorizontalDragEnd: (details) {\n"
    if marker not in t:
        print("player: art gesture miss — skip UI hint")
        return

    hint = """              if (context.watch<ModeProvider>().policy.preciseResume &&
                  music.canResumeCurrentQueueSong)
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
    t = t.replace(marker, hint, 1)

    # helper at class level - add before _showMoreOptions or at end of state class
    if "String _fmtMs" not in t:
        helper = """
  String _fmtMs(int ms) {
    final total = (ms / 1000).floor();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
"""
        if "  Future<void> _showMoreOptions" in t:
            t = t.replace(
                "  Future<void> _showMoreOptions",
                helper + "  Future<void> _showMoreOptions",
                1,
            )
        else:
            print("player: could not place _fmtMs")

    path.write_text(t)
    print("player: resume position chip")


def main() -> None:
    patch_music()
    patch_mode()
    patch_player_hint()
    print("precise resume done")


if __name__ == "__main__":
    main()
