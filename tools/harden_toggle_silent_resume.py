#!/usr/bin/env python3
"""Fix toggle (no fade), stuck midTransition skips fade, aggressive silent recover."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / 'lib/providers/music_provider.dart'


def try_replace(path: Path, old: str, new: str, label: str) -> bool:
    t = path.read_text()
    if old not in t:
        print('skip', label)
        return False
    path.write_text(t.replace(old, new, 1))
    print('ok', label)
    return True


def main() -> None:
    # --- togglePlayPause: route through pause / resumePlayback for fades ---
    t = MUSIC.read_text()
    # Find toggle body - may vary; use a robust match
    old_toggle_start = """  Future<void> togglePlayPause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(() async {
      try {
        // Decide from NATIVE state only. Optimistic isPlaying must not flip a
        // failed play() into a pause — that is the library-tap / auto-next bug.
        if (audioPlayer.playing) {
          _userWantsPlaying = false;
          await audioPlayer.pause();
          isPlaying = false;"""

    # Read current toggle fully
    i = t.find('Future<void> togglePlayPause')
    if i < 0:
        print('skip toggle — not found')
    else:
        # Find end of method roughly
        j = t.find('Future<void> pause({', i)
        if j < 0:
            j = t.find('\n  Future<void> pause', i)
        chunk = t[i:j] if j > i else t[i:i+1200]
        print('TOGGLE_CHUNK_LEN', len(chunk))
        print(chunk[:400])

        new_toggle = """  Future<void> togglePlayPause({String source = 'normal_player'}) {
    // Route through pause/resume so transport fades always apply.
    // Native playing state decides the branch (not optimistic isPlaying).
    if (audioPlayer.playing) {
      return pause(source: source);
    }
    return resumePlayback(source: source);
  }

"""
        # Replace from toggle to just before pause
        if j > i:
            t = t[:i] + new_toggle + t[j:]
            MUSIC.write_text(t)
            print('ok toggle_routes_fade')
        else:
            print('skip toggle end marker')

    # --- midTransition should NOT treat stuck automatic flag as "in crossfade" for fades ---
    # Use only _crossfadeInProgress || _repeatSelfHandoffInFlight for transport fades
    try_replace(
        MUSIC,
        """        final midTransition =
            _crossfadeInProgress || _automaticCrossfadeInFlight;
        // Soft fade-out for user (and short system) pause — skip mid-crossfade.
        if (!midTransition && audioPlayer.playing) {
          final from = audioPlayer.volume;
          final fadeMs = fromSystemFocus ? 120 : _transportFadeMs;
          await _fadePlayerVolume(audioPlayer, from, 0.0, durationMs: fadeMs);
        }""",
        """        // Only skip fade during a *real* volume ramp (not a stuck automatic flag).
        final midTransition =
            _crossfadeInProgress || _repeatSelfHandoffInFlight;
        if (!midTransition && audioPlayer.playing) {
          final from = audioPlayer.volume;
          final fadeMs = fromSystemFocus ? 120 : _transportFadeMs;
          await _fadePlayerVolume(audioPlayer, from, 0.0, durationMs: fadeMs);
        }""",
        'pause_mid_transition',
    )

    try_replace(
        MUSIC,
        """          final midTransition =
              _crossfadeInProgress || _automaticCrossfadeInFlight;
          final target = _eqPreampScale.clamp(0.0, 1.0);
          // Start quiet then fade in (skip mid-crossfade — ramp owns volume).
          if (!midTransition) {
            try {
              await audioPlayer.setVolume(0.0);
            } catch (_) {}
          }""",
        """          final midTransition =
              _crossfadeInProgress || _repeatSelfHandoffInFlight;
          final target = _eqPreampScale.clamp(0.0, 1.0);
          // Start quiet then fade in (skip only during a real ramp).
          if (!midTransition) {
            try {
              await audioPlayer.setVolume(0.0);
            } catch (_) {}
          }""",
        'resume_mid_transition',
    )

    # --- Silent recover: don't fight near end / completed / user pause ---
    try_replace(
        MUSIC,
        """  void _maybeRecoverSilentPlayback() {
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    if (!_userWantsPlaying) return;
    try {
      final active = audioPlayer;
      // Playing but muted, or wants play but engine not playing (BT route lag).
      final mutedWhilePlaying =
          active.playing && active.volume < 0.05;
      final wantsButStopped = !active.playing;
      if (!mutedWhilePlaying && !wantsButStopped) return;
      final now = DateTime.now();
      final cooldown = wantsButStopped
          ? const Duration(seconds: 2)
          : const Duration(seconds: 3);
      if (_lastSilentRecoverAt != null &&
          now.difference(_lastSilentRecoverAt!) < cooldown) {
        return;
      }
      _lastSilentRecoverAt = now;""",
        """  void _maybeRecoverSilentPlayback() {
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _transportInFlight ||
        _loadingSource) {
      return;
    }
    if (!_userWantsPlaying) return;
    try {
      final active = audioPlayer;
      final dur = active.duration ?? currentDuration;
      final pos = active.position;
      // Near end or completed: let completion / soft-loop own the next action.
      if (active.processingState == ProcessingState.completed) return;
      if (dur != null &&
          dur > Duration.zero &&
          pos >= dur - const Duration(seconds: 3)) {
        return;
      }
      // Playing but muted, or wants play but engine not playing (BT route lag).
      final mutedWhilePlaying =
          active.playing && active.volume < 0.05;
      final wantsButStopped = !active.playing;
      if (!mutedWhilePlaying && !wantsButStopped) return;
      final now = DateTime.now();
      final cooldown = wantsButStopped
          ? const Duration(seconds: 4)
          : const Duration(seconds: 5);
      if (_lastSilentRecoverAt != null &&
          now.difference(_lastSilentRecoverAt!) < cooldown) {
        return;
      }
      _lastSilentRecoverAt = now;""",
        'silent_recover_guard',
    )

    # --- Clear stale resume position on hard repeat-one ---
    try_replace(
        MUSIC,
        """        _lastCompletionSongId = null;
        currentPosition = Duration.zero;
        try {
          await audioPlayer.setVolume(_eqPreampScale.clamp(0.05, 1.0));
        } catch (_) {}
        await audioPlayer.seek(Duration.zero);
        try {
          audioPlayer.play();
        } catch (_) {}
        isPlaying = true;
        _userWantsPlaying = true;
        await _startHistoryEvent(currentSong!);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('completion_advance_result', {
          'result': 'repeated',
          'songId': currentSong?.id,
        });
        return;
      }""",
        """        _lastCompletionSongId = null;
        currentPosition = Duration.zero;
        // Do not resume mid-track after a failed loop — clear saved offset.
        if (_resumeSongId == currentSong?.id) {
          _resumePositionMs = 0;
          _resumeSongId = null;
        }
        if (currentSong != null) {
          _resumeBySongId.remove(currentSong!.id);
        }
        try {
          await audioPlayer.setVolume(_eqPreampScale.clamp(0.05, 1.0));
        } catch (_) {}
        await audioPlayer.seek(Duration.zero);
        try {
          audioPlayer.play();
        } catch (_) {}
        isPlaying = true;
        _userWantsPlaying = true;
        await _startHistoryEvent(currentSong!);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('completion_advance_result', {
          'result': 'repeated',
          'songId': currentSong?.id,
        });
        return;
      }""",
        'clear_resume_on_repeat',
    )

    print('toggle/silent/resume harden done')


if __name__ == '__main__':
    main()
