from pathlib import Path
import re

MUSIC = Path('lib/providers/music_provider.dart')
COORD = Path('lib/services/playback_coordinator.dart')

s = MUSIC.read_text()

# Remove the obsolete legacy serialization field; PlaybackCoordinator is authoritative.
s = s.replace("  Future<void> _playOperation = Future<void>.value();\n", "")

# Replace stop-both behavior with targeted engine cleanup.
old = re.search(r"  Future<void> _stopBoth\(\) async \{.*?\n  \}\n\n  Future<void> _enableEffects", s, re.S)
if not old:
    raise SystemExit('Could not locate _stopBoth block')
new = """  Future<void> _stopPlayer(AudioPlayer player) async {\n    try { await player.stop(); } catch (_) {}\n    try { await player.setLoopMode(LoopMode.off); } catch (_) {}\n    try { await player.setVolume(1.0); } catch (_) {}\n  }\n\n  Future<void> _stopBoth() async {\n    await _stopPlayer(_playerA);\n    await _stopPlayer(_playerB);\n  }\n\n  Future<void> _enableEffects"""
s = s[:old.start()] + new + s[old.end():]

# Replace _playSongInternal with true alternating-engine playback. First load is A;
# every subsequent source load uses the inactive engine, then commits it as active.
start = s.find("  Future<bool> _playSongInternal(")
end = s.find("\n  Future<void> _startHistoryEvent", start)
if start < 0 or end < 0:
    raise SystemExit('Could not locate _playSongInternal')
play = r'''  Future<bool> _playSongInternal(Song song, {List<Song>? queue, int startIndex = 0, bool resume = false, int? playbackIntentToken}) async {
    await _visibility.load();
    if (!_visibility.isVisible(song.id)) {
      await ResonateDiagnostics.record('playback_rejected_outside_library_scope', {'songId': song.id, 'stage': 'play_song_internal'});
      return false;
    }
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    if (!_playbackIntentGate.isCurrent(intentToken)) {
      await ResonateDiagnostics.record('playback_operation_stale', {'songId': song.id, 'stage': 'before_start', 'intentToken': intentToken, 'currentIntentToken': _playbackIntentGate.currentToken});
      return false;
    }
    if (song.filePath.trim().isEmpty) return false;

    final firstLoad = currentSong == null;
    final targetIsA = firstLoad ? true : !_activeIsA;
    final target = targetIsA ? _playerA : _playerB;
    final outgoing = firstLoad ? null : audioPlayer;
    final targetEq = targetIsA ? _equalizerA : _equalizerB;
    final targetLoud = targetIsA ? _loudnessA : _loudnessB;

    try {
      _crossfadeInProgress = false;
      unawaited(_finishHistoryEvent());

      // True A/B handoff: load the next source on the inactive engine. The
      // outgoing engine is paused only after we know which target we will use;
      // the target is the only engine whose source is replaced.
      if (outgoing != null && outgoing != target) {
        try { await outgoing.pause(); } catch (_) {}
      }
      try { await target.stop(); } catch (_) {}
      if (!_playbackIntentGate.isCurrent(intentToken)) {
        await ResonateDiagnostics.record('playback_operation_stale', {'songId': song.id, 'stage': 'after_stop', 'intentToken': intentToken, 'currentIntentToken': _playbackIntentGate.currentToken});
        return false;
      }

      final requested = queue != null && queue.isNotEmpty ? List<Song>.from(queue) : <Song>[song];
      final normalized = requested.where((s) => s.filePath.trim().isNotEmpty).toList();
      if (normalized.isEmpty) return false;
      var selectedIndex = normalized.indexWhere((s) => s.id == song.id);
      if (selectedIndex < 0) selectedIndex = startIndex.clamp(0, normalized.length - 1).toInt();
      final selectedSong = normalized[selectedIndex];
      final nextQueue = _shuffleEnabled && normalized.length > 1
          ? (() { final selected = normalized[selectedIndex]; final upcoming = <Song>[...normalized]..removeAt(selectedIndex)..shuffle(Random()); return <Song>[selected, ...upcoming]; })()
          : normalized;
      final nextIndex = _shuffleEnabled && normalized.length > 1 ? 0 : selectedIndex;

      await target.setLoopMode(LoopMode.off);
      await target.setAudioSource(AudioSource.uri(_audioUri(selectedSong.filePath), tag: selectedSong));
      if (!_playbackIntentGate.isCurrent(intentToken)) {
        await ResonateDiagnostics.record('playback_operation_stale', {'songId': selectedSong.id, 'stage': 'after_source_load', 'intentToken': intentToken, 'currentIntentToken': _playbackIntentGate.currentToken});
        try { await target.stop(); } catch (_) {}
        return false;
      }

      _queue = nextQueue;
      _queueIndex = nextIndex;
      currentSong = _queue[_queueIndex];
      _activeIsA = targetIsA;
      _lastCompletionSongId = null;
      currentDuration = currentSong!.duration;
      currentPosition = Duration.zero;
      isPlaying = false;
      await _persistQueue();
      _bindActivePlayerStreams();
      notifyListeners();

      if (resume && _resumeSongId == currentSong!.id && _resumePositionMs > 0) {
        final durationMs = currentDuration?.inMilliseconds ?? _resumePositionMs;
        final safeResume = _resumePositionMs.clamp(0, durationMs).toInt();
        await target.seek(Duration(milliseconds: safeResume));
        currentPosition = Duration(milliseconds: safeResume);
      }
      await _enableEffects(target, targetEq, targetLoud);
      await target.setVolume(1.0);
      if (!_playbackIntentGate.isCurrent(intentToken)) {
        await ResonateDiagnostics.record('playback_operation_stale', {'songId': currentSong!.id, 'stage': 'before_play', 'intentToken': intentToken, 'currentIntentToken': _playbackIntentGate.currentToken});
        try { await target.stop(); } catch (_) {}
        isPlaying = false;
        return false;
      }
      await target.play();
      if (!_playbackIntentGate.isCurrent(intentToken)) {
        try { await target.stop(); } catch (_) {}
        isPlaying = false;
        await ResonateDiagnostics.record('playback_operation_stale', {'songId': currentSong!.id, 'stage': 'after_play', 'intentToken': intentToken, 'currentIntentToken': _playbackIntentGate.currentToken});
        return false;
      }
      isPlaying = true;
      await _startHistoryEvent(currentSong!);
      _publishServiceState();
      notifyListeners();

      // Once the target is confirmed playing, release the outgoing engine.
      if (outgoing != null && outgoing != target) {
        try { await outgoing.stop(); } catch (_) {}
      }
      await ResonateDiagnostics.record('playback_engine_handoff', {
        'engine': targetIsA ? 'A' : 'B',
        'songId': currentSong!.id,
        'previousEngine': firstLoad ? null : (targetIsA ? 'B' : 'A'),
      });
      return true;
    } catch (e, stack) {
      isPlaying = false;
      debugPrint('Error playing song: $e');
      debugPrint('$stack');
      await ResonateDiagnostics.record('playback_operation_failed', {'songId': song.id, 'error': e.toString(), 'intentToken': intentToken});
      _publishServiceState();
      notifyListeners();
      return false;
    }
  }
'''
s = s[:start] + play + s[end:]

# Allow the coordinator to discard pending source requests that have already
# been superseded by a newer user/automatic transition intent.
old_sig = "Future<T> _serializePlayback<T>(Future<T> Function() operation, {required String command, required String source, bool userInitiated = false, int? intentToken}) async"
new_sig = "Future<T> _serializePlayback<T>(Future<T> Function() operation, {required String command, required String source, bool userInitiated = false, int? intentToken, Future<T> Function()? onSuperseded}) async"
if old_sig not in s:
    raise SystemExit('Could not locate _serializePlayback signature')
s = s.replace(old_sig, new_sig, 1)
old_return = "return _playbackCoordinator.runSourceMutation(operation, command: command);"
new_return = "return _playbackCoordinator.runSourceMutation(operation, command: command, supersedePending: userInitiated && const {'play', 'next', 'previous'}.contains(command), onSuperseded: onSuperseded);"
if old_return not in s:
    raise SystemExit('Could not locate coordinator return')
s = s.replace(old_return, new_return, 1)

# Provide deterministic fallback values for superseded requests.
s = s.replace("command: 'play', source: 'normal_player', userInitiated: true, intentToken: intentToken);", "command: 'play', source: 'normal_player', userInitiated: true, intentToken: intentToken, onSuperseded: () async => false);", 1)
s = s.replace("command: 'completion_advance',\n      source: 'automatic_transition',\n    );", "command: 'completion_advance',\n      source: 'automatic_transition',\n      onSuperseded: () async {},\n    );", 1)
s = s.replace("command: 'next', source: source, userInitiated: true, intentToken: intentToken);", "command: 'next', source: source, userInitiated: true, intentToken: intentToken, onSuperseded: () async {});", 1)
s = s.replace("command: 'previous', source: source, userInitiated: true, intentToken: intentToken);", "command: 'previous', source: source, userInitiated: true, intentToken: intentToken, onSuperseded: () async {});", 1)

MUSIC.write_text(s)

COORD.write_text('''import 'dart:async';\n\n/// Serializes native source mutations while allowing the newest source request\n/// to supersede requests that have not started yet. This prevents a burst of\n/// taps from becoming a long FIFO backlog while preserving the one-at-a-time\n/// native source mutation boundary.\nclass PlaybackCoordinator {\n  Future<void> _sourceTail = Future<void>.value();\n  int _operationId = 0;\n  int _latestSourceRequest = 0;\n\n  int get lastOperationId => _operationId;\n\n  Future<T> runSourceMutation<T>(\n    Future<T> Function() operation, {\n    required String command,\n    bool supersedePending = false,\n    Future<T> Function()? onSuperseded,\n  }) {\n    final id = ++_operationId;\n    if (supersedePending) _latestSourceRequest = id;\n    final next = _sourceTail.then((_) async {\n      if (supersedePending && id != _latestSourceRequest) {\n        if (onSuperseded != null) return onSuperseded();\n        return operation();\n      }\n      return operation();\n    });\n    _sourceTail = next.then<void>((_) {}, onError: (_, __) {});\n    return next;\n  }\n\n  Future<T> runTransport<T>(Future<T> Function() operation) => operation();\n\n  Future<void> drain() => _sourceTail;\n\n  void reset() {\n    _sourceTail = Future<void>.value();\n    _latestSourceRequest = _operationId;\n  }\n}\n''')

print('repair applied')
''