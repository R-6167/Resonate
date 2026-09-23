#!/usr/bin/env python3
from pathlib import Path
MP = Path(__file__).resolve().parents[1] / "lib/providers/music_provider.dart"

def main() -> int:
    t = MP.read_text()
    n = 0
    if "Clear any leftover DJ stretch" not in t:
        old = """  Future<bool> _playSongInternal(Song song, {List<Song>? queue, int startIndex = 0, bool resume = false, int? playbackIntentToken}) async {
    await _visibility.load();
    if (_visibility.isRestricted && !_visibility.isVisible(song.id)) {
      await ResonateDiagnostics.record('playback_rejected_outside_library_scope', {
        'songId': song.id,
        'stage': 'play_song_internal',
      });
      return false;
    }
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    if (song.filePath.trim().isEmpty) return false;

    // Phase 2: non-crossfade play always on Engine A (rebind if we were on B).
    _ensureEngineA(reason: 'play_song_internal');"""
        new = """  Future<bool> _playSongInternal(Song song, {List<Song>? queue, int startIndex = 0, bool resume = false, int? playbackIntentToken}) async {
    await _visibility.load();
    if (_visibility.isRestricted && !_visibility.isVisible(song.id)) {
      await ResonateDiagnostics.record('playback_rejected_outside_library_scope', {
        'songId': song.id,
        'stage': 'play_song_internal',
      });
      return false;
    }
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    if (song.filePath.trim().isEmpty) return false;

    // Clear any leftover DJ stretch / muted-engine state before a normal play.
    try {
      await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
    } catch (_) {}

    // Phase 2: non-crossfade play always on Engine A (rebind if we were on B).
    _ensureEngineA(reason: 'play_song_internal');"""
        if old in t:
            t = t.replace(old, new, 1)
            n += 1
            print("play internal")
        else:
            print("MISS play internal")

    old_catch = """    } catch (e, stack) {
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      debugPrint('True crossfade failed: $e'); debugPrint('$stack');
      try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {}
      await ResonateDiagnostics.record('crossfade_failed', {'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'error': e.toString(), 'intentToken': intentToken});"""
    new_catch = """    } catch (e, stack) {
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      debugPrint('True crossfade failed: $e'); debugPrint('$stack');
      try { await incoming.stop(); } catch (_) {}
      try { await outgoing.setSpeed(1.0); } catch (_) {}
      try { await incoming.setSpeed(1.0); } catch (_) {}
      try { await outgoing.setVolume(master); } catch (_) {}
      try {
        if (outgoing.playing && outgoing.volume < 0.02) {
          await outgoing.setVolume(master);
        }
      } catch (_) {}
      await ResonateDiagnostics.record('crossfade_failed', {'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'error': e.toString(), 'intentToken': intentToken});
      try {
        await ResonateDiagnostics.recordDj(
          stage: 'crossfade',
          outcome: 'failed',
          reason: e.toString(),
          songId: nextSong.id,
        );
      } catch (_) {}"""
    if old_catch in t:
        t = t.replace(old_catch, new_catch, 1)
        n += 1
        print("crossfade catch")
    elif "if (outgoing.playing && outgoing.volume < 0.02)" in t:
        print("crossfade catch already")
    else:
        print("MISS crossfade catch")

    MP.write_text(t)
    print("patches", n)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
