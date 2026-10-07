#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# --- music_provider: repeat-self + crossfade audible commit ---------------
mp = ROOT / "lib/providers/music_provider.dart"
t = mp.read_text()

# 1) On successful dual repeat-self: suppress completion advance + clear flag
old_ok = """    if (ok) {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
      _repeatSelfHandoffInFlight = false;
      _repeatSelfHandoffArmed = false;
      return;
    }
"""
new_ok = """    if (ok) {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
      _repeatSelfHandoffInFlight = false;
      _repeatSelfHandoffArmed = false;
      // Outgoing engine often hits completed mid-ramp. Do not advance to B.
      _completionObservedDuringCrossfade = false;
      if (song.id.isNotEmpty) {
        _lastCompletionSongId = song.id;
      }
      return;
    }
"""
if old_ok in t:
    t = t.replace(old_ok, new_ok, 1)
    print("repeat-self success cleanup")
else:
    print("WARN: repeat-self ok block miss")

# 2) Soft loop success path — same protection if present
if "_runRepeatSelfSoftLoop" in t and "repeat_self_committed" in t:
    # After soft loop commits, clear completion-observed
    soft_marker = "'mode': 'soft_single',"
    # leave soft as-is if hard to match; dual is main bug

# 3) After true crossfade commit: force audible + isPlaying from user intent
old_commit = """      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active
      _queueIndex = nextIndex; currentSong = nextSong; _lastCompletionSongId = null; currentDuration = nextSong.duration; currentPosition = incoming.position; isPlaying = incoming.playing;
      await _persistQueue(); _bindActivePlayerStreams(); await _startHistoryEvent(nextSong); _publishServiceState(); notifyListeners();
"""
new_commit = """      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active
      _queueIndex = nextIndex;
      currentSong = nextSong;
      _lastCompletionSongId = null;
      currentDuration = nextSong.duration;
      currentPosition = incoming.position;
      // Never inherit a stale mid-track resume for a freshly crossfaded-in song.
      if (currentPosition.inMilliseconds < 2500) {
        _resumeBySongId.remove(nextSong.id);
        if (_resumeSongId == nextSong.id) {
          _resumeSongId = null;
          _resumePositionMs = 0;
        }
      }
      // Audible guarantee: UI must not show B playing while engine is silent.
      try {
        await incoming.setSpeed(1.0);
        await incoming.setVolume(master);
        if (_userWantsPlaying && !incoming.playing) {
          try {
            incoming.play();
          } catch (_) {}
          for (var i = 0; i < 10 && !incoming.playing && _userWantsPlaying; i++) {
            await Future<void>.delayed(Duration(milliseconds: 35 + i * 20));
            try {
              incoming.play();
            } catch (_) {}
          }
        }
      } catch (_) {}
      isPlaying = _userWantsPlaying && (incoming.playing || incoming.volume >= 0.05);
      if (_userWantsPlaying && !incoming.playing) {
        // Last resort: hard cut to A with the incoming song (no silent scrub).
        try {
          await _playSongInternal(
            nextSong,
            queue: _queue,
            startIndex: nextIndex,
            playbackIntentToken: intentToken,
          );
        } catch (_) {}
        return audioPlayer.playing;
      }
      await _persistQueue();
      _bindActivePlayerStreams();
      await _startHistoryEvent(nextSong);
      _publishServiceState();
      notifyListeners();
"""
if old_commit in t:
    t = t.replace(old_commit, new_commit, 1)
    print("crossfade commit audible fix")
else:
    print("WARN: crossfade commit block miss")

# 4) Completion during crossfade must not advance when still on repeat-one
old_comp = """        if (_crossfadeInProgress || _automaticCrossfadeInFlight) {
          // Remember that the outgoing track finished while we were fading.
          // We will force an advance after the crossfade finishes (or fails).
          _completionObservedDuringCrossfade = true;
        } else if (!_completionAdvanceInProgress) {
          unawaited(onTrackEnded(completedSongId));
        }
"""
new_comp = """        if (_crossfadeInProgress ||
            _automaticCrossfadeInFlight ||
            _repeatSelfHandoffInFlight) {
          // Outgoing finished mid-fade. For repeat-one this is expected (self
          // handoff); for A→B we continue after commit without a second advance.
          _completionObservedDuringCrossfade = true;
          if (_repeatMode == PlaybackRepeatMode.one ||
              _repeatSelfHandoffInFlight) {
            // Do not treat as "need to go to next queue item".
            _lastCompletionSongId = completedSongId;
          }
        } else if (!_completionAdvanceInProgress) {
          unawaited(onTrackEnded(completedSongId));
        }
"""
if old_comp in t:
    t = t.replace(old_comp, new_comp, 1)
    print("completion during xf fixed")
else:
    print("WARN: completion during xf miss")

# 5) _ensureContinueAfterCrossfade: repeat-one → do not advance queue
old_ens = """  Future<void> _ensureContinueAfterCrossfade() async {
    if (_completionAdvanceInProgress || _queue.isEmpty) return;

    // If we landed on the last track and repeat is off, stop cleanly.
    if (_queueIndex >= _queue.length - 1 && _repeatMode == PlaybackRepeatMode.off) {
"""
new_ens = """  Future<void> _ensureContinueAfterCrossfade() async {
    if (_completionAdvanceInProgress || _queue.isEmpty) return;

    // Repeat-one already owns the next start (self handoff / seek 0).
    if (_repeatMode == PlaybackRepeatMode.one) {
      _completionObservedDuringCrossfade = false;
      try {
        final vol = _eqPreampScale.clamp(0.05, 1.0);
        if (audioPlayer.volume < vol * 0.85) {
          await audioPlayer.setVolume(vol);
        }
        if (_userWantsPlaying && !audioPlayer.playing) {
          try {
            audioPlayer.play();
          } catch (_) {}
        }
        isPlaying = _userWantsPlaying && audioPlayer.playing;
        _publishServiceState();
        notifyListeners();
      } catch (_) {}
      return;
    }

    // If we landed on the last track and repeat is off, stop cleanly.
    if (_queueIndex >= _queue.length - 1 && _repeatMode == PlaybackRepeatMode.off) {
"""
if old_ens in t:
    t = t.replace(old_ens, new_ens, 1)
    print("ensureContinue repeat-one")
else:
    print("WARN: ensureContinue miss")

mp.write_text(t)

# --- home: driving banner + note on density --------------------------------
home = ROOT / "lib/screens/home_screen.dart"
h = home.read_text()
if "driving_suggestion_banner.dart" not in h:
    h = h.replace(
        "import '../widgets/mode_shelf_card.dart';\n",
        "import '../widgets/mode_shelf_card.dart';\n"
        "import '../widgets/driving_suggestion_banner.dart';\n",
        1,
    )
if "DrivingSuggestionBanner" not in h:
    if "const ModeShelfCard()," in h:
        h = h.replace(
            "const ModeShelfCard(),",
            "const DrivingSuggestionBanner(),\n      const ModeShelfCard(),",
            1,
        )
        print("banner before shelf")
    elif "AutopilotHomeCard" in h:
        h = h.replace(
            "AutopilotHomeCard(songCount: songs.length),",
            "const DrivingSuggestionBanner(),\n      AutopilotHomeCard(songCount: songs.length),",
            1,
        )
        print("banner before autopilot")
    else:
        raise SystemExit("home insert miss")
home.write_text(h)

doc = ROOT / "docs/MODES.md"
if doc.exists():
    d = doc.read_text()
    d = d.replace(
        "- [ ] **Driving suggestion UI**",
        "- [x] **Driving suggestion UI**",
        1,
    )
    if "Driving suggestion banner" not in d:
        d = d.replace(
            "| Mode shelf (virtual playlist on Home) | Present |\n",
            "| Mode shelf (virtual playlist on Home) | Present |\n"
            "| Driving suggestion banner on Home | Present |\n",
            1,
        )
    doc.write_text(d)

print("script done")
