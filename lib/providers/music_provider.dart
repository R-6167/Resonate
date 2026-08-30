import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/song.dart';

class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;
  final AudioPlayer audioPlayer = AudioPlayer();

  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  List<Song> _queue = [];
  int _queueIndex = 0;

  MusicProvider({this.audioHandler}) {
    // Listen to audioHandler state if available
    audioHandler?.playbackState.listen((state) {
      // Map audioHandler playback state to local flags if desired
      final playing = state.playing;
      if (isPlaying != playing) {
        isPlaying = playing;
        notifyListeners();
      }
    });

    // just_audio local player streams for fallback/local playback
    audioPlayer.playerStateStream.listen((state) {
      final playing = state.playing;
      if (isPlaying != playing) {
        isPlaying = playing;
        notifyListeners();
      }
    });

    audioPlayer.positionStream.listen((pos) {
      currentPosition = pos;
      notifyListeners();
    });

    audioPlayer.durationStream.listen((d) {
      notifyListeners();
    });
  }

  Future<void> playSong(Song song) async {
    // Use AudioHandler if provided (unified background + foreground control)
    if (audioHandler != null) {
      final mediaItem = MediaItem(
        id: song.id,
        album: song.album,
        title: song.title,
        artist: song.artist,
        duration: song.duration,
        extras: {'filePath': song.filePath, 'albumArt': song.albumArt},
      );
      await audioHandler!.addQueueItem(mediaItem);
      await audioHandler!.play();
      // Update local state from mediaItem stream
      audioHandler!.mediaItem.listen((mi) {
        if (mi != null) {
          currentSong = Song(
            id: mi.id,
            title: mi.title,
            artist: mi.artist ?? '',
            album: mi.album ?? '',
            filePath: mi.extras?['filePath'] ?? '',
            duration: mi.duration ?? Duration.zero,
            dateAdded: DateTime.now(),
            albumArt: mi.extras?['albumArt'] as String?,
          );
          notifyListeners();
        }
      });
      return;
    }

    // Fallback to just_audio local playback
    try {
      if (currentSong?.id != song.id) {
        await audioPlayer.setAudioSource(AudioSource.uri(Uri.file(song.filePath)));
        currentSong = song;
      }
      await audioPlayer.play();
      isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error playing song locally: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (audioHandler != null) {
      final state = await audioHandler!.playbackState.first;
      if (state.playing) {
        await audioHandler!.pause();
      } else {
        await audioHandler!.play();
      }
      return;
    }

    if (audioPlayer.playing) {
      await audioPlayer.pause();
      isPlaying = false;
    } else {
      await audioPlayer.play();
      isPlaying = true;
    }
    notifyListeners();
  }

  Future<void> pause() async {
    if (audioHandler != null) {
      await audioHandler!.pause();
      return;
    }
    await audioPlayer.pause();
    isPlaying = false;
    notifyListeners();
  }

  Future<void> stop() async {
    if (audioHandler != null) {
      await audioHandler!.stop();
      return;
    }
    await audioPlayer.stop();
    isPlaying = false;
    currentSong = null;
    currentPosition = Duration.zero;
    notifyListeners();
  }

  Future<void> nextSong() async {
    if (audioHandler != null) {
      await audioHandler!.skipToNext();
      return;
    }
    if (_queue.isNotEmpty && _queueIndex < _queue.length - 1) {
      _queueIndex++;
      await playSong(_queue[_queueIndex]);
    }
  }

  Future<void> previousSong() async {
    if (audioHandler != null) {
      await audioHandler!.skipToPrevious();
      return;
    }
    if (_queue.isNotEmpty && _queueIndex > 0) {
      _queueIndex--;
      await playSong(_queue[_queueIndex]);
    }
  }

  Future<void> seek(Duration position) async {
    if (audioHandler != null) {
      await audioHandler!.seek(position);
      return;
    }
    await audioPlayer.seek(position);
    currentPosition = position;
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    if (audioHandler != null) {
      // audio_service does not provide volume control; keep local change
    }
    await audioPlayer.setVolume(v.clamp(0.0, 1.0));
    notifyListeners();
  }

  void setQueue(List<Song> songs, {int startIndex = 0}) {
    _queue = List.from(songs);
    _queueIndex = startIndex;
    if (audioHandler != null) {
      // Map to MediaItems and set via audio handler
      audioHandler!.setQueue(
        songs.map((s) => MediaItem(
              id: s.id,
              album: s.album,
              title: s.title,
              artist: s.artist,
              duration: s.duration,
              extras: {'filePath': s.filePath, 'albumArt': s.albumArt},
            )).toList(),
        startIndex: startIndex,
      );
    }
  }

  Stream<Duration?> get durationStream => audioPlayer.durationStream;
}
