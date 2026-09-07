from pathlib import Path
p = Path('lib/providers/music_provider.dart')
s = p.read_text()
old = """  Future<bool> performTrueCrossfade({required int milliseconds, String fadeType = 'linear'}) => _serializePlayback(() => _performTrueCrossfade(milliseconds: milliseconds, fadeType: fadeType, generation: _authority.beginAutomatic('crossfade')), command: 'crossfade', source: 'automatic_transition');

  Future<bool> _performTrueCrossfade({required int milliseconds, String fadeType = 'linear', required int generation}) async {
    if (!canCrossfadeNext || currentSong == null || !audioPlayer.playing) return false;
    final nextIndex = _queueIndex + 1; final nextSong = _queue[nextIndex]; if (nextSong.filePath.trim().isEmpty) return false;
    _crossfadeInProgress = true; final outgoing = audioPlayer; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _volume;
    try {
      await outgoing.setLoopMode(LoopMode.off); await incoming.stop(); await _loadSingle(incoming, incomingEq, incomingLoud, nextSong, start: false); await incoming.setVolume(0.0); await incoming.play();
      final total = milliseconds.clamp(500, 12000).toInt(); final steps = (total / 50).round().clamp(10, 240).toInt();
      for (var i = 1; i <= steps; i++) {
        if (_authority.isStale(generation)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} return false; }
        final linear = i / steps; final t = switch (fadeType) { 'ease_in' => linear * linear, 'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)), 'ease_in_out' => linear < 0.5 ? 2.0 * linear * linear : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0, _ => linear };
        await outgoing.setVolume(master * (1.0 - t)); await incoming.setVolume(master * t); await Future<void>.delayed(Duration(milliseconds: (total / steps).round()));
      }
      if (_authority.isStale(generation)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} return false; }
      await outgoing.pause(); await outgoing.setVolume(master); await incoming.setLoopMode(LoopMode.off); await incoming.setVolume(master); _activeIsA = !_activeIsA; _queueIndex = nextIndex; currentSong = nextSong; currentDuration = nextSong.duration; currentPosition = incoming.position; isPlaying = incoming.playing; await _finishHistoryEvent(); await _persistQueue(); _bindActivePlayerStreams(); await _startHistoryEvent(nextSong); _publishServiceState(); notifyListeners(); await outgoing.stop(); return true;
    } catch (e, stack) {
      debugPrint('True crossfade failed: $e');
      try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {}
      if (_authority.isStale(generation)) return false;
      try { await outgoing.stop(); await _playSongInternal(nextSong, queue: _queue, startIndex: nextIndex); return true; } catch (fallbackError) { debugPrint('Crossfade fallback failed: $fallbackError'); return false; }
    } finally { _crossfadeInProgress = false; notifyListeners(); }
  }
"""
new = """  Future<bool> performTrueCrossfade({required int milliseconds, String fadeType = 'linear'}) => _serializePlayback(() => _performTrueCrossfade(milliseconds: milliseconds, fadeType: fadeType, generation: _authority.beginAutomatic('crossfade')), command: 'crossfade', source: 'automatic_transition');

  Future<bool> _performTrueCrossfade({required int milliseconds, String fadeType = 'linear', required int generation, int? playbackIntentToken}) async {
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    if (!_playbackIntentGate.isCurrent(intentToken)) return false;
    if (!canCrossfadeNext || currentSong == null || !audioPlayer.playing) return false;
    final nextIndex = _queueIndex + 1; final nextSong = _queue[nextIndex]; if (nextSong.filePath.trim().isEmpty) return false;
    _crossfadeInProgress = true; final outgoing = audioPlayer; final outgoingSong = currentSong; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _volume;
    try {
      await outgoing.setLoopMode(LoopMode.off); await incoming.stop();
      await _loadSingle(incoming, incomingEq, incomingLoud, nextSong, start: false); await incoming.setVolume(0.0); await incoming.play();
      final total = milliseconds.clamp(500, 12000).toInt(); final steps = (total / 50).round().clamp(10, 240).toInt();
      for (var i = 1; i <= steps; i++) {
        if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'fade', 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
        final linear = i / steps; final t = switch (fadeType) { 'ease_in' => linear * linear, 'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)), 'ease_in_out' => linear < 0.5 ? 2.0 * linear * linear : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0, _ => linear };
        await outgoing.setVolume(master * (1.0 - t)); await incoming.setVolume(master * t); await Future<void>.delayed(Duration(milliseconds: (total / steps).round()));
      }
      if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'commit', 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
      // Finish the outgoing history record while currentSong still refers to it.
      // Mutating currentSong first caused history to be attributed to the next track.
      await _finishHistoryEvent();
      if (!_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} return false; }
      await outgoing.pause(); await outgoing.setVolume(master); await incoming.setLoopMode(LoopMode.off); await incoming.setVolume(master);
      _activeIsA = !_activeIsA; _queueIndex = nextIndex; currentSong = nextSong; currentDuration = nextSong.duration; currentPosition = incoming.position; isPlaying = incoming.playing;
      await _persistQueue(); _bindActivePlayerStreams(); await _startHistoryEvent(nextSong); _publishServiceState(); notifyListeners(); await outgoing.stop();
      await ResonateDiagnostics.record('crossfade_committed', {'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'queueIndex': _queueIndex, 'intentToken': intentToken});
      return true;
    } catch (e, stack) {
      debugPrint('True crossfade failed: $e'); debugPrint('$stack');
      try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {}
      await ResonateDiagnostics.record('crossfade_failed', {'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'error': e.toString(), 'intentToken': intentToken});
      if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) return false;
      try { await outgoing.stop(); await _playSongInternal(nextSong, queue: _queue, startIndex: nextIndex, playbackIntentToken: intentToken); return true; } catch (fallbackError) { debugPrint('Crossfade fallback failed: $fallbackError'); await ResonateDiagnostics.record('crossfade_fallback_failed', {'incomingSongId': nextSong.id, 'error': fallbackError.toString(), 'intentToken': intentToken}); return false; }
    } finally { _crossfadeInProgress = false; notifyListeners(); }
  }
"""
if old not in s: raise SystemExit('crossfade block not found')
s = s.replace(old, new, 1)
old2 = "final didCrossfade = await _performTrueCrossfade(milliseconds: _crossfadeDurationMs, fadeType: _crossfadeFadeType, generation: _authority.beginAutomatic('manual_next_crossfade'));"
new2 = "final didCrossfade = await _performTrueCrossfade(milliseconds: _crossfadeDurationMs, fadeType: _crossfadeFadeType, generation: _authority.beginAutomatic('manual_next_crossfade'), playbackIntentToken: intentToken);"
if old2 not in s: raise SystemExit('manual next call not found')
s = s.replace(old2, new2, 1)
old3 = "try { await database.updateListeningEvent(updated); }"
# no-op guard: actual source uses _database, so instrument its exact catch blocks below
old_start_catch = "try { await _database.insertListeningEvent(event); await _database.updateSongPlayCount(song.id); } catch (e) { debugPrint('Listening history start failed: $e'); }"
new_start_catch = "try { await _database.insertListeningEvent(event); await _database.updateSongPlayCount(song.id); } catch (e, stack) { debugPrint('Listening history start failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_start_failed', {'songId': song.id, 'error': e.toString(), 'stack': stack.toString()})); }"
if old_start_catch not in s: raise SystemExit('history start catch not found')
s = s.replace(old_start_catch, new_start_catch, 1)
old_finish_catch = "try { await _database.updateListeningEvent(updated); } catch (e) { debugPrint('Listening history finish failed: $e'); }"
new_finish_catch = "try { await _database.updateListeningEvent(updated); } catch (e, stack) { debugPrint('Listening history finish failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_finish_failed', {'songId': event.songId, 'error': e.toString(), 'stack': stack.toString()})); }"
if old_finish_catch not in s: raise SystemExit('history finish catch not found')
s = s.replace(old_finish_catch, new_finish_catch, 1)
p.write_text(s)
