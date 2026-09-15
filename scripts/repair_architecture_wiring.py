from pathlib import Path
p=Path('lib/providers/music_provider.dart'); s=p.read_text()
s=s.replace("import '../services/playback_authority.dart';","import '../services/playback_authority.dart';\nimport '../services/playback_coordinator.dart';") if "playback_coordinator.dart" not in s else s
s=s.replace("import '../services/audio_effects_bridge.dart';","import '../services/audio_effects_bridge.dart';\nimport '../services/audio_effects_controller.dart';") if "audio_effects_controller.dart" not in s else s
s=s.replace("final LibraryVisibilityStore _visibility = LibraryVisibilityStore.instance;","final LibraryVisibilityStore _visibility = LibraryVisibilityStore.instance;\n  final PlaybackCoordinator _playbackCoordinator = PlaybackCoordinator();\n  late final AudioEffectsController _audioEffectsController;") if '_playbackCoordinator' not in s else s
needle="    _playerB = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB, _loudnessB]));"
if '_audioEffectsController = AudioEffectsController(' not in s:
 s=s.replace(needle,needle+"\n    _audioEffectsController = AudioEffectsController(equalizerA: _equalizerA, equalizerB: _equalizerB, loudnessA: _loudnessA, loudnessB: _loudnessB);")
s=s.replace("""    if (userInitiated && const {'toggle', 'pause', 'stop', 'seek'}.contains(command) && audioPlayer.audioSource != null) {\n      return operation();\n    }\n    final next = _playOperation.then((_) => operation());\n    _playOperation = next.then<void>((_) {}, onError: (_, __) {});\n    return next;""","""    if (userInitiated && const {'toggle', 'pause', 'stop', 'seek'}.contains(command) && audioPlayer.audioSource != null) {\n      return _playbackCoordinator.runTransport(operation);\n    }\n    return _playbackCoordinator.runSourceMutation(operation, command: command);""")
start=s.find('  Future<void> _enableEffects(')
end=s.find('\n  Future<T> _serializePlayback',start)
if start>=0 and end>start:
 s=s[:start]+"""  Future<void> _enableEffects(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud) async {\n    try { await _audioEffectsController.activateFor(player); } catch (e) { debugPrint('Audio effects activation failed: $e'); }\n  }\n"""+s[end:]
p.write_text(s)
print('ok')
