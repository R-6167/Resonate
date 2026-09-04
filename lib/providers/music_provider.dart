import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/audio_service_handler.dart';
import '../services/database_helper.dart';

class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;
  late final AudioPlayer _playerA;
  late final AudioPlayer _playerB;
  late final AndroidEqualizer _equalizerA;
  late final AndroidEqualizer _equalizerB;
  late final AndroidLoudnessEnhancer _loudnessA;
  late final AndroidLoudnessEnhancer _loudnessB;
  bool _activeIsA = true;
  AudioPlayer get audioPlayer => _activeIsA ? _playerA : _playerB;
  AudioPlayer get inactivePlayer => _activeIsA ? _playerB : _playerA;
  AndroidEqualizer get equalizer => _activeIsA ? _equalizerA : _equalizerB;
  AndroidLoudnessEnhancer get loudnessEnhancer => _activeIsA ? _loudnessA : _loudnessB;
  AndroidEqualizer get inactiveEqualizer => _activeIsA ? _equalizerB : _equalizerA;
  AndroidLoudnessEnhancer get inactiveLoudnessEnhancer => _activeIsA ? _loudnessB : _loudnessA;
  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration? currentDuration;
  double _volume = 1.0;
  List<Song> _queue = [];
  int _queueIndex = 0;
  bool _crossfadeInProgress = false;
  bool _completionAdvanceInProgress = false;
  bool _queueRestoreInProgress = false;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;
  double get volume => _volume;
  List<Song> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  List<Song> get upcomingQueue => List.unmodifiable(_queue.skip(_queueIndex + 1));
  bool get canCrossfadeNext => _queueIndex < _queue.length - 1 && !_crossfadeInProgress;

  static const _savedQueueIdsKey = 'playback_queue_song_ids';
  static const _savedQueueIndexKey = 'playback_queue_index';

  MusicProvider({this.audioHandler}) {
    _equalizerA = AndroidEqualizer(); _equalizerB = AndroidEqualizer();
    _loudnessA = AndroidLoudnessEnhancer(); _loudnessB = AndroidLoudnessEnhancer();
    _playerA = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerA, _loudnessA]));
    _playerB = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB, _loudnessB]));
    if (audioHandler is AudioServiceHandler) {
      (audioHandler! as AudioServiceHandler).bindPlaybackController(onPlay: togglePlayPause, onPause: pause, onStop: stop, onSeek: seek, onNext: nextSong, onPrevious: previousSong);
    }
    _bindActivePlayerStreams();
    unawaited(_configureAudioSession());
    unawaited(_restoreQueue());
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin && (event.type == AudioInterruptionType.pause || event.type == AudioInterruptionType.duck)) unawaited(pause());
      });
      _noisySubscription = session.becomingNoisyEventStream.listen((_) { if (isPlaying) unawaited(pause()); });
    } catch (e) { debugPrint('Audio session setup failed: $e'); }
  }

  Future<void> _restoreQueue() async {
    if (_queueRestoreInProgress) return;
    _queueRestoreInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_savedQueueIdsKey) ?? const <String>[];
      if (ids.isEmpty || currentSong != null || _queue.isNotEmpty) return;
      final savedIndex = prefs.getInt(_savedQueueIndexKey) ?? 0;
      final songs = await DatabaseHelper().getAllSongs();
      final byId = <String, Song>{for (final song in songs) song.id: song};
      final restored = ids.map((id) => byId[id]).whereType<Song>().toList();
      if (restored.isEmpty) return;
      _queue = restored;
      _queueIndex = savedIndex.clamp(0, restored.length - 1);
      currentSong = _queue[_queueIndex];
      currentDuration = currentSong!.duration;
      currentPosition = Duration.zero;
      notifyListeners();
    } catch (e) {
      debugPrint('Playback queue restore failed: $e');
    } finally {
      _queueRestoreInProgress = false;
    }
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isEmpty) {
        await prefs.remove(_savedQueueIdsKey);
        await prefs.remove(_savedQueueIndexKey);
        return;
      }
      await prefs.setStringList(_savedQueueIdsKey, _queue.map((song) => song.id).toList());
      await prefs.setInt(_savedQueueIndexKey, _queueIndex);
    } catch (e) {
      debugPrint('Playback queue persistence failed: $e');
    }
  }

  void _publishServiceState() {
    final handler = audioHandler;
    if (handler is AudioServiceHandler) handler.publishPlayback(song: currentSong, playing: isPlaying, position: currentPosition, duration: currentDuration, speed: 1.0);
  }

  void _bindActivePlayerStreams() {
    _playerStateSubscription?.cancel(); _positionSubscription?.cancel(); _durationSubscription?.cancel(); _volumeSubscription?.cancel();
    final player = audioPlayer;
    _playerStateSubscription = player.playerStateStream.listen((state) {
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (isPlaying != playing) { isPlaying = playing; notifyListeners(); _publishServiceState(); }
      if (state.processingState == ProcessingState.completed) {
        isPlaying = false; notifyListeners(); _publishServiceState();
        if (!_completionAdvanceInProgress && !_crossfadeInProgress && _queueIndex < _queue.length - 1) unawaited(_advanceAfterCompletion());
      }
    });
    _positionSubscription = player.positionStream.listen((position) { if (currentPosition != position) { currentPosition = position; notifyListeners(); _publishServiceState(); } });
    _durationSubscription = player.durationStream.listen((duration) { if (duration != null && currentDuration != duration) { currentDuration = duration; notifyListeners(); _publishServiceState(); } });
    _volumeSubscription = player.volumeStream.listen((value) { if (_volume != value) { _volume = value; notifyListeners(); } });
  }

  Future<void> _advanceAfterCompletion() async { if (_completionAdvanceInProgress) return; _completionAdvanceInProgress = true; try { await nextSong(); } finally { _completionAdvanceInProgress = false; } }
  Uri _audioUri(String value) { final path = value.trim(); if (path.startsWith('content://') || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('file://')) return Uri.parse(path); return Uri.file(path); }
  Future<void> _stopBoth() async { try { await _playerA.stop(); } catch (_) {} try { await _playerB.stop(); } catch (_) {} try { await _playerA.setLoopMode(LoopMode.off); } catch (_) {} try { await _playerB.setLoopMode(LoopMode.off); } catch (_) {} try { await _playerA.setVolume(_volume); } catch (_) {} try { await _playerB.setVolume(_volume); } catch (_) {} }
  Future<void> _enableEffects(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud) async { try { await eq.setEnabled(true); } catch (e) { debugPrint('Equalizer unavailable: $e'); } try { await loud.setEnabled(true); } catch (e) { debugPrint('Loudness enhancer unavailable: $e'); } }

  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0}) async {
    if (song.filePath.trim().isEmpty) return false;
    try {
      _crossfadeInProgress = false; await _stopBoth(); _activeIsA = true;
      final requested = queue != null && queue.isNotEmpty ? List<Song>.from(queue) : [song];
      final normalized = requested.where((s) => s.filePath.trim().isNotEmpty).toList(); if (normalized.isEmpty) return false;
      final selectedIndex = normalized.indexWhere((s) => s.id == song.id);
      _queue = normalized; _queueIndex = selectedIndex >= 0 ? selectedIndex : startIndex.clamp(0, normalized.length - 1);
      currentSong = _queue[_queueIndex]; currentDuration = currentSong!.duration; currentPosition = Duration.zero; isPlaying = false;
      await _persistQueue();
      _bindActivePlayerStreams(); notifyListeners();
      await audioPlayer.setAudioSource(AudioSource.uri(_audioUri(currentSong!.filePath), tag: currentSong));
      await _enableEffects(audioPlayer, equalizer, loudnessEnhancer); await audioPlayer.setVolume(_volume); await audioPlayer.play();
      isPlaying = true; _publishServiceState(); notifyListeners(); return true;
    } catch (e, stack) { isPlaying = false; debugPrint('Error playing song: $e'); debugPrint('$stack'); _publishServiceState(); notifyListeners(); return false; }
  }

  Future<bool> enqueueSongs(List<Song> songs) async {
    final additions = songs.where((s) => s.filePath.trim().isNotEmpty && !_queue.any((q) => q.id == s.id)).toList();
    if (additions.isEmpty) return false; _queue.addAll(additions); await _persistQueue(); notifyListeners(); return true;
  }

  Future<bool> addToQueue(Song song) => enqueueSongs([song]);

  Future<bool> playNext(Song song) async {
    if (song.filePath.trim().isEmpty || currentSong?.id == song.id) return false;
    if (_queue.any((queued) => queued.id == song.id)) return false;
    final insertAt = (_queueIndex + 1).clamp(0, _queue.length);
    _queue.insert(insertAt, song);
    await _persistQueue();
    notifyListeners();
    return true;
  }

  Future<bool> removeFromQueue(int index) async {
    if (index <= _queueIndex || index >= _queue.length) return false;
    _queue.removeAt(index); await _persistQueue(); notifyListeners(); return true;
  }

  Future<bool> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex <= _queueIndex || oldIndex >= _queue.length) return false;
    if (newIndex > oldIndex) newIndex--;
    newIndex = newIndex.clamp(_queueIndex + 1, _queue.length - 1);
    final item = _queue.removeAt(oldIndex); _queue.insert(newIndex, item); await _persistQueue(); notifyListeners(); return true;
  }

  void clearUpcomingQueue() { if (_queueIndex >= _queue.length - 1) return; _queue = [..._queue.take(_queueIndex + 1)]; unawaited(_persistQueue()); notifyListeners(); }
  Future<void> _loadSingle(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud, Song song, {bool start = true}) async { await player.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song)); await _enableEffects(player, eq, loud); await player.setVolume(start ? _volume : 0.0); if (start) await player.play(); }

  Future<bool> performTrueCrossfade({required int milliseconds, String fadeType = 'linear'}) async {
    if (!canCrossfadeNext || currentSong == null || !audioPlayer.playing) return false;
    final nextIndex = _queueIndex + 1, nextSong = _queue[nextIndex]; if (nextSong.filePath.trim().isEmpty) return false;
    _crossfadeInProgress = true; final outgoing = audioPlayer, incoming = inactivePlayer, incomingEq = inactiveEqualizer, incomingLoud = inactiveLoudnessEnhancer, master = _volume;
    try {
      await outgoing.setLoopMode(LoopMode.one); await incoming.stop(); await _loadSingle(incoming, incomingEq, incomingLoud, nextSong, start: false); await incoming.setLoopMode(LoopMode.one); await incoming.setVolume(0.0); await incoming.play();
      final total = milliseconds.clamp(500, 12000), steps = (total / 50).round().clamp(10, 240);
      for (var i = 1; i <= steps; i++) { if (!outgoing.playing) break; final linear = i / steps; final t = switch (fadeType) { 'ease_in' => linear * linear, 'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)), 'ease_in_out' => linear < 0.5 ? 2.0 * linear * linear : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0, _ => linear }; await outgoing.setVolume(master * (1.0 - t)); await incoming.setVolume(master * t); await Future<void>.delayed(Duration(milliseconds: (total / steps).round())); }
      await outgoing.pause(); await outgoing.setVolume(master); await incoming.setVolume(master); _activeIsA = !_activeIsA; _queueIndex = nextIndex; currentSong = nextSong; currentDuration = nextSong.duration; currentPosition = incoming.position; isPlaying = incoming.playing; await _persistQueue(); _bindActivePlayerStreams(); _publishServiceState(); notifyListeners(); await outgoing.stop(); return true;
    } catch (e, stack) { debugPrint('True crossfade failed: $e'); debugPrint('$stack'); try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} return false; } finally { _crossfadeInProgress = false; notifyListeners(); }
  }

  Future<void> togglePlayPause() async { try { if (audioPlayer.playing) await audioPlayer.pause(); else if (audioPlayer.audioSource != null) await audioPlayer.play(); else if (currentSong != null) await playSong(currentSong!, queue: _queue.isEmpty ? null : _queue, startIndex: _queueIndex); } catch (e) { debugPrint('Playback toggle failed: $e'); } }
  Future<void> pause() async { try { await audioPlayer.pause(); _publishServiceState(); } catch (_) {} }
  Future<void> stop() async { await _stopBoth(); isPlaying = false; currentPosition = Duration.zero; _publishServiceState(); notifyListeners(); }
  Future<void> nextSong() async { if (_queueIndex >= _queue.length - 1) return; await playSong(_queue[_queueIndex + 1], queue: _queue, startIndex: _queueIndex + 1); }
  Future<void> previousSong() async { if (_queueIndex > 0) await playSong(_queue[_queueIndex - 1], queue: _queue, startIndex: _queueIndex - 1); else await audioPlayer.seek(Duration.zero); }
  Future<void> seek(Duration position) async { try { final duration = audioPlayer.duration ?? currentDuration ?? Duration.zero; final safe = Duration(milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds)); await audioPlayer.seek(safe); _publishServiceState(); } catch (_) {} }
  Future<void> setVolume(double volume) async { _volume = volume.clamp(0.0, 1.0).toDouble(); try { await audioPlayer.setVolume(_volume); if (!inactivePlayer.playing) await inactivePlayer.setVolume(_volume); notifyListeners(); } catch (_) {} }
  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async { if (songs.isEmpty) { _queue = []; _queueIndex = 0; await _persistQueue(); notifyListeners(); return; } final index = startIndex.clamp(0, songs.length - 1); await playSong(songs[index], queue: songs, startIndex: index); }
  Stream<Duration?> get durationStream => audioPlayer.durationStream;
  @override void dispose() { _playerStateSubscription?.cancel(); _positionSubscription?.cancel(); _durationSubscription?.cancel(); _volumeSubscription?.cancel(); _interruptionSubscription?.cancel(); _noisySubscription?.cancel(); _playerA.dispose(); _playerB.dispose(); super.dispose(); }
}
