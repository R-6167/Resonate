from pathlib import Path
p=Path('lib/providers/music_provider.dart')
s=p.read_text()
s=s.replace("  Future<void> _duckForInterruption() async { try { await audioPlayer.setVolume(_volume * .35); } catch (_) {} }", "  Future<void> _duckForInterruption() async { try { await audioPlayer.setVolume(.35); } catch (_) {} }")
s=s.replace("_volumeSubscription = player.volumeStream.listen((value) { if (_volume != value) { _volume = value; notifyListeners(); } });", "// App volume is sourced from Android STREAM_MUSIC. Do not mirror the player's\n    // internal gain into _volume or it will overwrite the system-volume value.")
s=s.replace("try { await _playerA.setVolume(_volume); } catch (_) {} try { await _playerB.setVolume(_volume); } catch (_) {}", "try { await _playerA.setVolume(1.0); } catch (_) {} try { await _playerB.setVolume(1.0); } catch (_) {}")
s=s.replace("await audioPlayer.setVolume(_volume);\n      if (!_playbackIntentGate.isCurrent(intentToken))", "await audioPlayer.setVolume(1.0);\n      if (!_playbackIntentGate.isCurrent(intentToken))")
p.write_text(s)
print('volume repair applied')
