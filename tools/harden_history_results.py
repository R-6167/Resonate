from pathlib import Path
p = Path('lib/providers/music_provider.dart')
s = p.read_text()
old = "try { await _database.insertListeningEvent(event); await _database.updateSongPlayCount(song.id); } catch (e, stack) { debugPrint('Listening history start failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_start_failed', {'songId': song.id, 'error': e.toString(), 'stack': stack.toString()})); }"
new = "try { final inserted = await _database.insertListeningEvent(event); final playCount = await _database.updateSongPlayCount(song.id); if (inserted < 0 || playCount < 0) { unawaited(ResonateDiagnostics.record('listening_history_start_failed', {'songId': song.id, 'insertResult': inserted, 'playCountResult': playCount})); } } catch (e, stack) { debugPrint('Listening history start failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_start_failed', {'songId': song.id, 'error': e.toString(), 'stack': stack.toString()})); }"
if old not in s: raise SystemExit('start block not found')
s = s.replace(old, new, 1)
old2 = "try { await _database.updateListeningEvent(updated); } catch (e, stack) { debugPrint('Listening history finish failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_finish_failed', {'songId': event.songId, 'error': e.toString(), 'stack': stack.toString()})); }"
new2 = "try { final updatedRows = await _database.updateListeningEvent(updated); if (updatedRows < 0 || updatedRows == 0) { unawaited(ResonateDiagnostics.record('listening_history_finish_failed', {'songId': event.songId, 'eventId': event.id, 'updateResult': updatedRows})); } } catch (e, stack) { debugPrint('Listening history finish failed: $e'); unawaited(ResonateDiagnostics.record('listening_history_finish_failed', {'songId': event.songId, 'error': e.toString(), 'stack': stack.toString()})); }"
if old2 not in s: raise SystemExit('finish block not found')
s = s.replace(old2, new2, 1)
p.write_text(s)
