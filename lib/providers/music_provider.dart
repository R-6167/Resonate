import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';

class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;

  late final AndroidEqualizer equalizer;
  late final AndroidLoudnessEnhancer loudnessEnhancer;
  late final AudioPlayer audioPlayer;

  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration? currentDuration;
  double _volume = 1.0;
  List<Song> _queue = [];
  int _queueIndex = 0;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<double>? _volumeSubscription;

  double get volume => _volume;

  MusicProvider({this.audioHandler}) {
    equalizer = AndroidEqualizer();
    loudnessEnhancer = AndroidLoudnessEnhancer();
    audioPlayer = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [equalizer, loudnessEnhancer],
      ),
    );
    _initialize();
  }

  void _initialize() {
    _playerStateSubscription = audioPlayer.playerStateStream.listen((state) {
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (isPlaying != playing) {
        isPlaying = playing;
        notifyListeners();
      }
      if (state.processingState == ProcessingState.completed) {
        isPlaying = false;
        notifyListeners();
      }
    });
    _positionSubscription = audioPlayer.positionStream.listen((position) {
      if (currentPosition != position) {
        currentPosition = position;
        notifyListeners();
      }
    });
    _durationSubscription = audioPlayer.durationStream.listen((duration) {
      if (duration != null && currentDuration != duration) {
        currentDuration = duration;
        notifyListeners();
      }
    });
    _volumeSubscription = audioPlayer.volumeStream.listen((value) {
      if (_volume != value) {
        _volume = value;
        notifyListeners();
      }
    });
  }

  Uri _audioUri(String value) {
    final path = value.trim();
    if (path.startsWith('content://') ||
        path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('file://')) {
      return Uri.parse(path);
    }
    return Uri.file(path);
  }

  Future<bool> playSong(
    Song song, {
    List<Song>? queue,
    int startIndex = 0,
  }) async {
    final path = song.filePath.trim();
    if (path.isEmpty) {
      debugPrint('Cannot play song: empty file path for ${song.title}');
      return false;
    }

    currentSong = song;
    currentDuration = song.duration;
    currentPosition = Duration.zero;
    isPlaying = false;
    notifyListeners();

    try {
      _queue = queue != null && queue.isNotEmpty ? List<Song>.from(queue) : [song];
      _queueIndex = queue != null && queue.isNotEmpty
          ? startIndex.clamp(0, _queue.length - 1)
          : 0;

      if (_queue.length > 1) {
        final sources = _queue
            .where((item) => item.filePath.trim().isNotEmpty)
            .map((item) => AudioSource.uri(
                  _audioUri(item.filePath),
                  tag: item,
                ))
            .toList();
        if (sources.isEmpty) return false;
        await audioPlayer.setAudioSource(
          ConcatenatingAudioSource(
            children: sources,
            useLazyPreparation: true,
          ),
          initialIndex: _queueIndex.clamp(0, sources.length - 1),
        );
      } else {
        await audioPlayer.setAudioSource(
          AudioSource.uri(_audioUri(path), tag: song),
        );
      }

      // Effects are attached to the player pipeline. They are harmless at
      // zero gain and can then be adjusted live from the settings screens.
      await equalizer.setEnabled(true);
      await loudnessEnhancer.setEnabled(true);

      await audioPlayer.play();
      isPlaying = true;
      notifyListeners();
      return true;
    } catch (e, stack) {
      isPlaying = false;
      debugPrint('Error playing song: $e');
      debugPrint('$stack');
      notifyListeners();
      return false;
    }
  }

  Future<void> togglePlayPause() async {
    try {
      if (audioPlayer.playing) {
        await audioPlayer.pause();
      } else if (audioPlayer.audioSource != null) {
        await audioPlayer.play();
      } else if (currentSong != null) {
        await playSong(currentSong!, queue: _queue.isEmpty ? null : _queue, startIndex: _queueIndex);
      }
    } catch (e) {
      debugPrint('Playback toggle failed: $e');
      isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    try {
      await audioPlayer.pause();
    } catch (e) {
      debugPrint('Pause failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await audioPlayer.stop();
      isPlaying = false;
      currentPosition = Duration.zero;
      notifyListeners();
    } catch (e) {
      debugPrint('Stop failed: $e');
    }
  }

  Future<void> nextSong() async {
    try {
      if (_queueIndex < _queue.length - 1) {
        _queueIndex++;
        final song = _queue[_queueIndex];
        await playSong(song, queue: _queue, startIndex: _queueIndex);
      }
    } catch (e) {
      debugPrint('Next song failed: $e');
    }
  }

  Future<void> previousSong() async {
    try {
      if (_queueIndex > 0) {
        _queueIndex--;
        final song = _queue[_queueIndex];
        await playSong(song, queue: _queue, startIndex: _queueIndex);
      } else {
        await audioPlayer.seek(Duration.zero);
      }
    } catch (e) {
      debugPrint('Previous song failed: $e');
    }
  }

  Future<void> seek(Duration position) async {
    try {
      final duration = audioPlayer.duration ?? currentDuration ?? Duration.zero;
      final safe = Duration(
        milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds),
      );
      await audioPlayer.seek(safe);
    } catch (e) {
      debugPrint('Seek failed: $e');
    }
  }

  Future<void> setVolume(double volume) async {
    final safe = volume.clamp(0.0, 1.0).toDouble();
    try {
      await audioPlayer.setVolume(safe);
      _volume = safe;
      notifyListeners();
    } catch (e) {
      debugPrint('Volume change failed: $e');
    }
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) {
      _queue = [];
      _queueIndex = 0;
      return;
    }
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
    audioPlayer.dispose();
    super.dispose();
  }
}
