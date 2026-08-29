import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import 'package:provider/provider.dart';
import 'library_provider.dart';

class MusicProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final AudioHandler? _audioHandler;
  Song? _current;
  bool _isPlaying = false;

  // Queue state
  List<Song> _queue = [];
  int _queueIndex = -1;

  MusicProvider([this._audioHandler]) {
    _init();
  }

  Song? get currentSong => _current;
  bool get isPlaying => _isPlaying;
  AudioPlayer get player => _player;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player.playbackEventStream.listen((event) {
      final playing = _player.playing;
      if (playing != _isPlaying) {
        _isPlaying = playing;
        notifyListeners();
      }

      // If playback completed, advance queue
      if (_player.processingState == ProcessingState.completed) {
        skipNext();
      }
    });

    _player.playerStateStream.listen((state) {
      // notify on state changes so UI can respond to buffering/completed
      notifyListeners();
    });
  }

  Future<void> setQueueFromSongs(List<Song> songs, {int startIndex = 0}) async {
    _queue = List.from(songs);
    _queueIndex = (startIndex >= 0 && startIndex < _queue.length) ? startIndex : 0;
    await _playQueueIndex(_queueIndex);
    notifyListeners();
  }

  Future<void> _playQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final song = _queue[index];
    _queueIndex = index;
    _current = song;
    try {
      if (_audioHandler != null) {
        final item = MediaItem(
          id: song.id,
          album: song.album,
          title: song.title,
          artist: song.artist,
          duration: Duration(milliseconds: song.duration),
          extras: {'path': song.path},
        );
        await _audioHandler!.addQueueItem(item);
        await _audioHandler!.play();
      }
      await _player.setFilePath(song.path);
      await _player.play();
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing queue index $index: $e');
    }
  }

  Future<void> playSong(Song song) async {
    try {
      // If song is in queue, play at that index
      final idx = _queue.indexWhere((s) => s.id == song.id);
      if (idx != -1) {
        await _playQueueIndex(idx);
        return;
      }

      _current = song;
      if (_audioHandler != null) {
        try {
          final item = MediaItem(
            id: song.id,
            album: song.album,
            title: song.title,
            artist: song.artist,
            duration: Duration(milliseconds: song.duration),
            extras: {'path': song.path},
          );
          await _audioHandler!.addQueueItem(item);
          await _audioHandler!.play();
        } catch (_) {
          await _player.setFilePath(song.path);
          await _player.play();
        }
      } else {
        await _player.setFilePath(song.path);
        await _player.play();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing song: $e');
    }
  }

  Future<void> playPause() async {
    if (_player.playing) {
      await _player.pause();
      _audioHandler?.pause();
    } else {
      await _player.play();
      _audioHandler?.play();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _audioHandler?.stop();
    _current = null;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _audioHandler?.seek(position);
  }

  Future<void> setCrossfade(Duration duration) async {
    try {
      await _player.setCrossFadeEnabled(true);
      await _player.setCrossfadeDuration(duration);
    } catch (e) {
      debugPrint('Crossfade not supported or error: $e');
    }
  }

  Future<void> skipNext() async {
    if (_queue.isEmpty) return;
    final next = _queueIndex + 1;
    if (next >= _queue.length) {
      // stop at end
      await stop();
      return;
    }
    await _playQueueIndex(next);
  }

  Future<void> skipPrevious() async {
    if (_queue.isEmpty) return;
    final prev = _queueIndex - 1;
    if (prev < 0) {
      await seek(Duration.zero);
      return;
    }
    await _playQueueIndex(prev);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
