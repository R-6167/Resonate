from pathlib import Path
p = Path('lib/providers/music_provider.dart')
s = p.read_text()
repls = {
"Future<void> togglePlayPause({String source = 'normal_player'}) => _serializePlayback(() async {": "Future<void> togglePlayPause({String source = 'normal_player'}) { final intentToken = _playbackIntentGate.issue(); return _serializePlayback(() async { if (!_playbackIntentGate.isCurrent(intentToken)) return;",
"command: 'toggle', source: source, userInitiated: source != 'system' && source != 'automatic_transition');": "command: 'toggle', source: source, userInitiated: true, intentToken: intentToken); }",
"Future<void> pause({String source = 'normal_player'}) => _serializePlayback(() async {": "Future<void> pause({String source = 'normal_player'}) { final intentToken = _playbackIntentGate.issue(); return _serializePlayback(() async { if (!_playbackIntentGate.isCurrent(intentToken)) return;",
"command: 'pause', source: source, userInitiated: source != 'system' && source != 'automatic_transition');": "command: 'pause', source: source, userInitiated: true, intentToken: intentToken); }",
"Future<void> stop({String source = 'normal_player'}) => _serializePlayback(() async {": "Future<void> stop({String source = 'normal_player'}) { final intentToken = _playbackIntentGate.issue(); return _serializePlayback(() async { if (!_playbackIntentGate.isCurrent(intentToken)) return;",
"command: 'stop', source: source, userInitiated: source != 'system' && source != 'automatic_transition');": "command: 'stop', source: source, userInitiated: true, intentToken: intentToken); }",
"Future<void> nextSong({String source = 'normal_player'}) => _serializePlayback(() async {": "Future<void> nextSong({String source = 'normal_player'}) { final intentToken = _playbackIntentGate.issue(); return _serializePlayback(() async { if (!_playbackIntentGate.isCurrent(intentToken)) return;",
"command: 'next', source: source, userInitiated: source != 'automatic_transition');": "command: 'next', source: source, userInitiated: true, intentToken: intentToken); }",
"Future<void> previousSong({String source = 'normal_player'}) => _serializePlayback(() async {": "Future<void> previousSong({String source = 'normal_player'}) { final intentToken = _playbackIntentGate.issue(); return _serializePlayback(() async { if (!_playbackIntentGate.isCurrent(intentToken)) return;",
"command: 'previous', source: source, userInitiated: source != 'automatic_transition');": "command: 'previous', source: source, userInitiated: true, intentToken: intentToken); }",
"Future<void> seek(Duration position, {String source = 'normal_player'}) => _serializePlayback(() async {": "Future<void> seek(Duration position, {String source = 'normal_player'}) { final intentToken = _playbackIntentGate.issue(); return _serializePlayback(() async { if (!_playbackIntentGate.isCurrent(intentToken)) return;",
"command: 'seek', source: source, userInitiated: source != 'automatic_transition');": "command: 'seek', source: source, userInitiated: true, intentToken: intentToken); }",
}
for old,new in repls.items():
    if old not in s:
        raise SystemExit(f'missing expected text: {old[:100]}')
    s=s.replace(old,new,1)
p.write_text(s)
