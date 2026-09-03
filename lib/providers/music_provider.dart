import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../services/audio_service_handler.dart';

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

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;

  double get volume => _volume;
  List<Song> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  bool get canCrossfadeNext => _queueIndex < _queue.length - 1 && !_crossfadeInProgress;

  MusicProvider({this.audioHandler}) {
    _equalizerA = AndroidEqualizer();
    _equalizerB = AndroidEqualizer();
    _loudnessA = AndroidLoudnessEnhancer();
    _loudnessB = AndroidLoudnessEnhancer();
    _playerA = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerA, _loudnessA]));
    _playerB = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB, _loudnessB]));
    if (audioHandler is AudioServiceHandler) {
      (audioHandler! as AudioServiceHandler).bindPlaybackController(
        onPlay: () => togglePlayPause(),
        onPause: pause,
        onStop: stop,
        onSeek: seek,
        onNext: nextSong,
        onPrevious: previousSong,
      );
    }
    _bindActivePlayerStreams();
    unawaited(_configureAudioSession());
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSubscription = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          if (event.type == AudioInterruptionType.pause || event.type == AudioInterruptionType.duck) {
            unawaited(pause());
          }
        }
      });
      _noisySubscription = session.becomingNoisyEventStream.listen((_) {
        if (isPlaying) unawaited(pause());
      });
    } catch (e) {
      debugPrint('Audio session setup failed: $e');
    }
  }

  void _publishServiceState() {
    final handler = audioHandler;
    if (handler is AudioServiceHandler) {
      handler.publishPlayback(
        song: currentSong,
        playing: isPlaying,
        position: currentPosition,
        duration: currentDuration,
        speed: 1.0,
      );
    }
  }

  void _bindActivePlayerStreams() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _volumeSubscription?.cancel();
    final player = audioPlayer;
    _playerStateSubscription = player.playerStateStream.listen((state) {
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (isPlaying != playing) { isPlaying = playing; notifyListeners(); _publishServiceState(); }
      if (state.processingState == ProcessingState.completed) { isPlaying = false; notifyListeners(); _publishServiceState(); }
    });
    _positionSubscription = player.positionStream.listen((position) {
      if (currentPosition != position) { currentPosition = position; notifyListeners(); _publishServiceState(); }
    });
    _durationSubscription = player.durationStream.listen((duration) {
      if (duration != null && currentDuration != duration) { currentDuration = duration; notifyListeners(); _publishServiceState(); }
    });
    _volumeSubscription = player.volumeStream.listen((value) {
      if (_volume != value) { _volume = value; notifyListeners(); }
    });
  }

  Uri _audioUri(String value) {
    final path = value.trim();
    if (path.startsWith('content://') || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('file://')) return Uri.parse(path);
    return Uri.file(path);
  }

  Future<void> _stopBoth() async {
    try { await _playerA.stop(); } catch (_) {}
    try { await _playerB.stop(); } catch (_) {}
    try { await _playerA.setLoopMode(LoopMode.off); } catch (_) {}
    try { await _playerB.setLoopMode(LoopMode.off); } catch (_) {}
    try { await _playerA.setVolume(_volume); } catch (_) {}
    try { await _playerB.setVolume(_volume); } catch (_) {}
  }

  Future<void> _loadSingle(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud, Song song, {bool start = true}) async {
    await player.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song));
    await eq.setEnabled(true);
    await loud.setEnabled(true);
    await player.setVolume(start ? _volume : 0.0);
    if (start) await player.play();
  }

  Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0}) async {
    if (song.filePath.trim().isEmpty) return false;
    try {
      _crossfadeInProgress = false;
      await _stopBoth();
      _activeIsA = true;
      _queue = queue != null && queue.isNotEmpty ? List<Song>.from(queue) : [song];
      _queueIndex = queue != null && queue.isNotEmpty ? startIndex.clamp(0, _queue.length - 1) : 0;
      currentSong = song;
      currentDuration = song.duration;
      currentPosition = Duration.zero;
      isPlaying = false;
      _bindActivePlayerStreams();
      notifyListeners();

      if (_queue.length > 1) {
        final sources = _queue.where((s) => s.filePath.trim().isNotEmpty).map((s) => AudioSource.uri(_audioUri(s.filePath), tag: s)).toList();
        if (sources.isEmpty) return false;
        await audioPlayer.setAudioSource(ConcatenatingAudioSource(children: sources, useLazyPreparation: true), initialIndex: _queueIndex.clamp(0, sources.length - 1));
        await equalizer.setEnabled(true);
        await loudnessEnhancer.setEnabled(true);
        await audioPlayer.setVolume(_volume);
      } else {
        await _loadSingle(audioPlayer, equalizer, loudnessEnhancer, song);
      }
      await audioPlayer.play();
      isPlaying = true;
      _publishServiceState();
      notifyListeners();
      return true;
    } catch (e, stack) {
      isPlaying = false;
      debugPrint('Error playing song: $e');
      debugPrint('$stack');
      _publishServiceState();
      notifyListeners();
      return false;
    }
  }

  Future<bool> performTrueCrossfade({required int milliseconds, String fadeType = 'linear'}) async {
    if (!canCrossfadeNext || currentSong == null || !audioPlayer.playing) return false;
    final nextIndex = _queueIndex + 1;
    final nextSong = _queue[nextIndex];
    if (nextSong.filePath.trim().isEmpty) return false;
    _crossfadeInProgress = true;
    final outgoing = audioPlayer;
    final incoming = inactivePlayer;
    final incomingEq = inactiveEqualizer;
    final incomingLoud = inactiveLoudnessEnhancer;
    final master = _volume;
    try {
      await outgoing.setLoopMode(LoopMode.one);
      await incoming.stop();
      await _loadSingle(incoming, incomingEq, incomingLoud, nextSong, start: false);
      await incoming.setLoopMode(LoopMode.one);
      await incoming.setVolume(0.0);
      await incoming.play();
      final total = milliseconds.clamp(500, 12000);
      final steps = (total / 50).round().clamp(10, 240);
      for (var i = 1; i <= steps; i++) {
        if (!outgoing.playing) break;
        final linear = i / steps;
        final t = switch (fadeType) {
          'ease_in' => linear * linear,
          'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)),
          'ease_in_out' => linear < 0.5 ? 2.0 * linear * linear : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0,
          _ => linear,
        };
        await outgoing.setVolume(master * (1.0 - t));
        await incoming.setVolume(master * t);
        await Future<void>.delayed(Duration(milliseconds: (total / steps).round()));
      }
      await outgoing.pause();
      await outgoing.setVolume(master);
      await incoming.setVolume(master);
      _activeIsA = !_activeIsA;
      _queueIndex = nextIndex;
      currentSong = nextSong;
      currentDuration = nextSong.duration;
      currentPosition = incoming.position;
      isPlaying = incoming.playing;
      _bindActivePlayerStreams();
      _publishServiceState();
      notifyListeners();
      await outgoing.stop();
      return true;
    } catch (e, stack) {
      debugPrint('True crossfade failed: $e');
      debugPrint('$stack');
      try { await incoming.stop(); } catch (_) {}
      try { await outgoing.setVolume(master); } catch (_) {}
      return false;
    } finally {
      _crossfadeInProgress = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    try {
      if (audioPlayer.playing) await audioPlayer.pause();
      else if (audioPlayer.audioSource != null) await audioPlayer.play();
      else if (currentSong != null) await playSong(currentSong!, queue: _queue.isEmpty ? null : _queue, startIndex: _queueIndex);
    } catch (e) { debugPrint('Playback toggle failed: $e'); }
  }

  Future<void> pause() async { try { await audioPlayer.pause(); _publishServiceState(); } catch (_) {} }

  Future<void> stop() async {
    await _stopBoth();
    isPlaying = false;
    currentPosition = Duration.zero;
    _publishServiceState();
    notifyListeners();
  }

  Future<void> nextSong() async {
    if (_queueIndex >= _queue.length - 1) return;
    await playSong(_queue[_queueIndex + 1], queue: _queue, startIndex: _queueIndex + 1);
  }

  Future<void> previousSong() async {
    if (_queueIndex > 0) await playSong(_queue[_queueIndex - 1], queue: _queue, startIndex: _queueIndex - 1);
    else await audioPlayer.seek(Duration.zero);
  }

  Future<void> seek(Duration position) async {
    try {
      final duration = audioPlayer.duration ?? currentDuration ?? Duration.zero;
      final safe = Duration(milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds));
      await audioPlayer.seek(safe);
      _publishServiceState();
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    try {
      await audioPlayer.setVolume(_volume);
      if (!inactivePlayer.playing) await inactivePlayer.setVolume(_volume);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) { _queue = []; _queueIndex = 0; return; }
    final index = startIndex.clamp(0, songs.length - 1);
    await playSong(songs[index], queue: songs, startIndex: index);
  }

  Stream<Duration?> get durationStream => audioPlayer.durationStream;

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _volumeSubscription?.cancel();
    _interruptionSubscription?.cancel();
    _noisySubscription?.cancel();
    _playerA.dispose();
    _playerB.dispose();
    super.dispose();
  }
}
