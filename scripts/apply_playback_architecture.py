from pathlib import Path
import re

BRANCH = 'Companion_Features_Diagnostics'

def replace_once(path, old, new):
    p = Path(path); s = p.read_text()
    if old not in s:
        raise SystemExit(f'Expected text not found in {path}: {old[:160]!r}')
    p.write_text(s.replace(old, new, 1))

p = Path('lib/providers/music_provider.dart')
s = p.read_text()

replace_once('lib/providers/music_provider.dart',
    "import '../services/audio_effects_bridge.dart';",
    "import '../services/audio_effects_bridge.dart';\nimport '../services/audio_effects_controller.dart';\nimport '../services/playback_coordinator.dart';")

replace_once('lib/providers/music_provider.dart',
    "  final PlaybackIntentGate _playbackIntentGate = PlaybackIntentGate();",
    "  final PlaybackIntentGate _playbackIntentGate = PlaybackIntentGate();\n  final PlaybackCoordinator _playbackCoordinator = PlaybackCoordinator();\n  late final AudioEffectsController _audioEffectsController;")

replace_once('lib/providers/music_provider.dart',
    "    _loudnessB = AndroidLoudnessEnhancer();\n    _playerA = AudioPlayer",
    "    _loudnessB = AndroidLoudnessEnhancer();\n    _audioEffectsController = AudioEffectsController(equalizerA: _equalizerA, equalizerB: _equalizerB, loudnessA: _loudnessA, loudnessB: _loudnessB);\n    _playerA = AudioPlayer")

# Refresh the in-memory source after replace_once writes. The previous migration
# accidentally overwrote these successful insertions with the stale pre-edit buffer.
s = p.read_text()

# Replace the provider's duplicated A/B effect implementation with the single controller.
s = re.sub(
    r"  Future<void> syncSavedAudioEffects\(\) async \{.*?\n  \}\n\n  Future<void> _configureAudioSession",
    "  Future<void> syncSavedAudioEffects() async {\n    try { await _audioEffectsController.syncAll(); } catch (e) { debugPrint('Saved audio effects sync failed: $e'); }\n  }\n\n  Future<void> _configureAudioSession",
    s, count=1, flags=re.S)

# Replace the activation helper with the centralized controller.
s = re.sub(
    r"  Future<void> _enableEffects\(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud\) async \{.*?\n  \}\n\n  Future<T> _serializePlayback",
    "  Future<void> _enableEffects(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud) async {\n    try { await _audioEffectsController.activateFor(player); } catch (e) { debugPrint('Audio effects activation failed: $e'); }\n  }\n\n  Future<T> _serializePlayback",
    s, count=1, flags=re.S)

# Route every existing playback operation through the coordinator's explicit lanes.
s = re.sub(
    r"  Future<T> _serializePlayback<T>\(Future<T> Function\(\) operation, \{required String command, required String source, bool userInitiated = false, int\? intentToken\}\) async \{.*?\n  \}\n\n  Future<bool> playSong",
    """  Future<T> _serializePlayback<T>(Future<T> Function() operation, {required String command, required String source, bool userInitiated = false, int? intentToken}) async {
    final effectiveIntent = userInitiated ? (intentToken ?? _playbackIntentGate.issue()) : _playbackIntentGate.currentToken;
    if (userInitiated) {
      _authority.markExternalUserCommand(source, command);
      unawaited(ResonateDiagnostics.record('playback_command_accepted', {
        'command': command, 'source': source, 'intentToken': effectiveIntent,
      }));
    }
    final transportPriority = userInitiated &&
        const {'toggle', 'pause', 'stop', 'seek'}.contains(command) &&
        audioPlayer.audioSource != null;
    await ResonateDiagnostics.record('playback_operation_queued', {
      'command': command,
      'source': source,
      'userInitiated': userInitiated,
      'intentToken': effectiveIntent,
      'lane': transportPriority ? 'transport_priority' : 'source_serialized',
    });
    if (transportPriority) {
      return _playbackCoordinator.runTransport(operation);
    }
    return _playbackCoordinator.runSourceMutation(operation, command: command);
  }

  Future<bool> playSong""",
    s, count=1, flags=re.S)

# The service should receive the real queue, not a one-item shadow queue.
s = s.replace(
    "  void _publishServiceState() { final handler = audioHandler; if (handler is AudioServiceHandler) handler.publishPlayback(song: currentSong, playing: isPlaying, position: currentPosition, duration: currentDuration, speed: 1.0); }",
    "  void _publishServiceState() { final handler = audioHandler; if (handler is AudioServiceHandler) handler.publishPlayback(song: currentSong, playing: isPlaying, position: currentPosition, duration: currentDuration, speed: 1.0, bufferedPosition: audioPlayer.bufferedPosition, playbackQueue: _queue, queueIndex: _queueIndex); }",
    1)

p.write_text(s)

# Update the service bridge to expose the authoritative queue.
handler = Path('lib/services/audio_service_handler.dart')
h = handler.read_text()
h = h.replace(
    "    required double speed,\n    Duration? bufferedPosition,",
    "    required double speed,\n    Duration? bufferedPosition,\n    List<Song>? playbackQueue,\n    int queueIndex = 0,")
h = h.replace(
    "    if (song != null) {\n      final item = songToMediaItem(song);\n      mediaItem.add(item);\n      _items\n        ..clear()\n        ..add(item);\n      queue.add(List.unmodifiable(_items));",
    "    final sourceQueue = (playbackQueue ?? (song == null ? const <Song>[] : <Song>[song]))\n        .where((item) => item.filePath.trim().isNotEmpty)\n        .map(songToMediaItem)\n        .toList();\n    if (sourceQueue.isNotEmpty) {\n      _items\n        ..clear()\n        ..addAll(sourceQueue);\n      queue.add(List.unmodifiable(_items));\n      final safeIndex = queueIndex.clamp(0, _items.length - 1);\n      mediaItem.add(_items[safeIndex]);",
    1)
handler.write_text(h)

# Keep About truthful for this stabilization milestone.
about = Path('lib/screens/about_screen.dart')
a = about.read_text()
a = a.replace('0.1.2 • Local-first intelligent music player', '0.1.3 • Local-first intelligent music player', 1)
a = a.replace('Implemented in 0.1.2', 'Implemented in 0.1.3', 1)
if 'Playback architecture hardening' not in a:
    a = a.replace('  - duplicate completion protection/safer track-end transitions', '  - duplicate completion protection/safer track-end transitions\n  - centralized playback mutation coordination\n  - single authoritative media-session queue/state bridge', 1)
about.write_text(a)

Path('scripts/apply_playback_architecture.py').unlink()