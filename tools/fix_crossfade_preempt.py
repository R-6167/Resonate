#!/usr/bin/env python3
"""Fix: tapping a song during crossfade must not jump back to the planned next track."""
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "lib/providers/music_provider.dart"
t = path.read_text()

if "_userTransportEpoch" in t and "crossfade_preempted_by_user" in t:
    print("already patched")
    raise SystemExit(0)

# 1) Field next to _automaticTransitionGeneration
if "_userTransportEpoch" not in t:
    old = "  int _automaticTransitionGeneration = 0;\n"
    # find the field - may vary
    import re
    m = re.search(r"  int _automaticTransitionGeneration = 0;\n", t)
    if not m:
        # try without spaces
        raise SystemExit("automaticTransitionGeneration field miss")
    t = t.replace(
        "  int _automaticTransitionGeneration = 0;\n",
        "  int _automaticTransitionGeneration = 0;\n"
        "  /// Bumped on every user transport (play/next/prev/pause). Automatic\n"
        "  /// crossfade captures this and aborts if it changes mid-flight.\n"
        "  int _userTransportEpoch = 0;\n",
        1,
    )
    print("added _userTransportEpoch")

# 2) Strengthen cancel
old_cancel = """  void _cancelAutomaticPlaybackWork() {
    // Invalidate all in-flight automatic A/B work before starting the user's
    // transport operation. Old futures may still unwind, but cannot commit.
    _automaticTransitionGeneration++;
    _automaticCrossfadeInFlight = false;
    _crossfadeInProgress = false;
    _completionAdvanceInProgress = false;
    _completionObservedDuringCrossfade = false;
    _preloadedNextSongId = null;
    _crossfadePreloadInFlight = false;
"""
new_cancel = """  void _cancelAutomaticPlaybackWork() {
    // Invalidate all in-flight automatic A/B work before starting the user's
    // transport operation. Old futures may still unwind, but cannot commit.
    _userTransportEpoch++;
    _automaticTransitionGeneration++;
    _automaticCrossfadeInFlight = false;
    _crossfadeInProgress = false;
    _completionAdvanceInProgress = false;
    _completionObservedDuringCrossfade = false;
    _preloadedNextSongId = null;
    _crossfadePreloadInFlight = false;
    // Hard-silence the idle engine so a dying crossfade cannot keep audible B.
    unawaited(() async {
      try {
        await _playerB.pause();
      } catch (_) {}
      try {
        await _playerB.setVolume(0.0);
      } catch (_) {}
      try {
        await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
      } catch (_) {}
    }());
"""
if old_cancel not in t:
    raise SystemExit("cancel block miss")
t = t.replace(old_cancel, new_cancel, 1)
print("cancel hardened")

# 3) Guard _maybeStartAutomaticCrossfade against transport/load
old_maybe = """  void _maybeStartAutomaticCrossfade(Duration position) {
    if (!_crossfadeEnabled || !audioPlayer.playing) return;
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight) {
      return;
    }
"""
new_maybe = """  void _maybeStartAutomaticCrossfade(Duration position) {
    if (!_crossfadeEnabled || !audioPlayer.playing) return;
    // Never arm auto-crossfade while the user is driving transport or loading.
    if (_transportInFlight || _loadingSource) return;
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight) {
      return;
    }
"""
if old_maybe not in t:
    raise SystemExit("maybeStart block miss")
t = t.replace(old_maybe, new_maybe, 1)
print("maybeStart gated")

# 4) _runAutomaticCrossfade — capture epoch, abort on user preempt
old_run = """  Future<void> _runAutomaticCrossfade() async {
    final generation = _authority.beginAutomatic('automatic_crossfade');
    final transitionMarker = _automaticTransitionGeneration + 1;
    final fromIndex = _queueIndex;
    final fromSongId = currentSong?.id;
    try {
"""
new_run = """  Future<void> _runAutomaticCrossfade() async {
    final generation = _authority.beginAutomatic('automatic_crossfade');
    final transitionMarker = _automaticTransitionGeneration + 1;
    final epoch = _userTransportEpoch;
    final fromIndex = _queueIndex;
    final fromSongId = currentSong?.id;
    if (_transportInFlight || _loadingSource) {
      _automaticCrossfadeInFlight = false;
      return;
    }
    try {
"""
if old_run not in t:
    raise SystemExit("runAutomatic block miss")
t = t.replace(old_run, new_run, 1)
print("runAutomatic epoch capture")

# After performTrueCrossfade failure check — include epoch
old_fb1 = """      if (ok) return;
      if (_automaticTransitionGeneration != transitionMarker ||
          _authority.isStale(generation) ||
          currentSong?.id != fromSongId || _queueIndex != fromIndex) {
        await ResonateDiagnostics.record('crossfade_fallback_skipped_already_advanced', {
"""
new_fb1 = """      if (ok) return;
      if (_userTransportEpoch != epoch ||
          _automaticTransitionGeneration != transitionMarker ||
          _authority.isStale(generation) ||
          currentSong?.id != fromSongId ||
          _queueIndex != fromIndex) {
        await ResonateDiagnostics.record('crossfade_fallback_skipped_already_advanced', {
          'preempted': _userTransportEpoch != epoch,
"""
if old_fb1 not in t:
    raise SystemExit("fallback skip check miss")
t = t.replace(old_fb1, new_fb1, 1)
print("fallback skip includes epoch")

# Soft fallback pre-play check
old_fb2 = """      await _softFadeOutActive(milliseconds: 500);
      if (_automaticTransitionGeneration != transitionMarker ||
          _authority.isStale(generation) ||
          currentSong?.id != fromSongId || _queueIndex != fromIndex) return;
      final nextIdx = fromIndex < _queue.length - 1
"""
new_fb2 = """      await _softFadeOutActive(milliseconds: 500);
      if (_userTransportEpoch != epoch ||
          _automaticTransitionGeneration != transitionMarker ||
          _authority.isStale(generation) ||
          currentSong?.id != fromSongId ||
          _queueIndex != fromIndex) {
        await ResonateDiagnostics.record('crossfade_preempted_by_user', {
          'stage': 'fallback_soft',
          'fromSongId': fromSongId,
        });
        return;
      }
      final nextIdx = fromIndex < _queue.length - 1
"""
if old_fb2 not in t:
    raise SystemExit("fallback soft check miss")
t = t.replace(old_fb2, new_fb2, 1)
print("fallback soft epoch gated")

# Catch block fallback — same epoch guard
old_catch = """    } catch (e) {
      debugPrint('automatic crossfade error: $e');
      if (_automaticTransitionGeneration == transitionMarker &&
          !_authority.isStale(generation) &&
          currentSong?.id == fromSongId && _queueIndex == fromIndex) {
"""
new_catch = """    } catch (e) {
      debugPrint('automatic crossfade error: $e');
      if (_userTransportEpoch == epoch &&
          _automaticTransitionGeneration == transitionMarker &&
          !_authority.isStale(generation) &&
          currentSong?.id == fromSongId &&
          _queueIndex == fromIndex) {
"""
if old_catch not in t:
    print("WARNING catch block miss — may already differ")
else:
    t = t.replace(old_catch, new_catch, 1)
    print("catch fallback epoch gated")

# 5) playSong — record preempt diagnostic when cancelling active crossfade
old_play = """  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0, bool resumeIfPossible = false, int? resumeAtMs}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    _lastCompletionSongId = null;
"""
new_play = """  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0, bool resumeIfPossible = false, int? resumeAtMs}) {
    final intentToken = _playbackIntentGate.issue();
    final wasXf = _crossfadeInProgress || _automaticCrossfadeInFlight;
    _cancelAutomaticPlaybackWork();
    if (wasXf) {
      unawaited(ResonateDiagnostics.record('crossfade_preempted_by_user', {
        'stage': 'play_song',
        'requestedSongId': song.id,
        'wasSongId': currentSong?.id,
        'queueIndex': _queueIndex,
      }));
    }
    _lastCompletionSongId = null;
"""
if old_play not in t:
    raise SystemExit("playSong block miss")
t = t.replace(old_play, new_play, 1)
print("playSong preempt diagnostic")

# 6) _playSongInternal — promote engine A and stop competing B at begin
old_begin = """    try {
      _crossfadeInProgress = false;
      _automaticCrossfadeInFlight = false;
      unawaited(_finishHistoryEvent());
      await step('begin');

      // Quiet B; pause A only if needed. Avoid stop() — drops focus on some OEMs.
      try {
        await _playerB.pause();
      } catch (_) {}
      try {
        await _playerB.setVolume(0.0);
      } catch (_) {}
      try {
        if (target.playing) await target.pause();
      } catch (_) {}
"""
new_begin = """    try {
      _crossfadeInProgress = false;
      _automaticCrossfadeInFlight = false;
      unawaited(_finishHistoryEvent());
      await step('begin');

      // User play always owns Engine A. Kill any dying crossfade on B first.
      _ensureEngineA(reason: 'play_song');
      try {
        await _playerB.pause();
      } catch (_) {}
      try {
        await _playerB.setVolume(0.0);
      } catch (_) {}
      try {
        await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
      } catch (_) {}
      try {
        if (target.playing) await target.pause();
      } catch (_) {}
"""
if old_begin not in t:
    print("WARNING playSongInternal begin miss")
else:
    t = t.replace(old_begin, new_begin, 1)
    print("playSongInternal engine A ownership")

# 7) Fade loop — also check user transport epoch (capture at crossfade start)
# Inject epoch into _performTrueCrossfade
old_perf = """  Future<bool> _performTrueCrossfade({required int milliseconds, String fadeType = 'linear', required int generation, int? playbackIntentToken}) async {
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    final transitionGeneration = ++_automaticTransitionGeneration;
"""
new_perf = """  Future<bool> _performTrueCrossfade({required int milliseconds, String fadeType = 'linear', required int generation, int? playbackIntentToken}) async {
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    final transitionGeneration = ++_automaticTransitionGeneration;
    final transportEpoch = _userTransportEpoch;
"""
if old_perf not in t:
    raise SystemExit("performTrueCrossfade header miss")
t = t.replace(old_perf, new_perf, 1)
print("performTrueCrossfade epoch")

# Patch fade-loop cancel condition to include epoch
old_fade_chk = """        if (_automaticTransitionGeneration != transitionGeneration ||
            _authority.isStale(generation) ||
            !_playbackIntentGate.isCurrent(intentToken)) {
          try { await incoming.stop(); } catch (_) {}
          try { await outgoing.setVolume(master); } catch (_) {}
          await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'fade',
"""
new_fade_chk = """        if (_userTransportEpoch != transportEpoch ||
            _automaticTransitionGeneration != transitionGeneration ||
            _authority.isStale(generation) ||
            !_playbackIntentGate.isCurrent(intentToken)) {
          try { await incoming.stop(); } catch (_) {}
          try { await outgoing.setVolume(master); } catch (_) {}
          await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'fade',
            'preempted': _userTransportEpoch != transportEpoch,
"""
if old_fade_chk not in t:
    raise SystemExit("fade check miss")
t = t.replace(old_fade_chk, new_fade_chk, 1)
print("fade loop epoch gated")

# Commit-stage cancel check (one-liner form)
old_commit = """      if (_automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(base); } catch (_) {} await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'commit', 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
"""
new_commit = """      if (_userTransportEpoch != transportEpoch ||
          _automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(base); } catch (_) {} await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'commit', 'preempted': _userTransportEpoch != transportEpoch, 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
"""
if old_commit not in t:
    print("WARNING commit check miss")
else:
    t = t.replace(old_commit, new_commit, 1)
    print("commit stage epoch gated")

path.write_text(t)
print("crossfade preempt fix applied")
