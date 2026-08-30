import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../services/audio_service_handler.dart';

class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;

  final AudioPlayer audioPlayer = AudioPlayer();

  Song? currentSong;

  bool isPlaying = false;

  Duration currentPosition = Duration.zero;

  Duration? currentDuration;

  List<Song> _queue = [];

  int _queueIndex = 0;

  StreamSubscription<PlaybackState>? _handlerPlaybackSubscription;
  StreamSubscription<MediaItem?>? _handlerMediaItemSubscription;

  MusicProvider({
    this.audioHandler,
  }) {
    _initialize();
  }

  // ---------------------------------------------------------------------------
  // INITIALIZATION
  // ---------------------------------------------------------------------------

  void _initialize() {
    // Background audio service state.
    if (audioHandler != null) {
      _handlerPlaybackSubscription =
          audioHandler!.playbackState.listen(
        (state) {
          final newPlaying = state.playing;

          final newPosition =
              state.updatePosition;

          bool changed = false;

          if (isPlaying != newPlaying) {
            isPlaying = newPlaying;
            changed = true;
          }

          if (currentPosition != newPosition) {
            currentPosition = newPosition;
            changed = true;
          }

          if (changed) {
            notifyListeners();
          }
        },
      );

      _handlerMediaItemSubscription =
          audioHandler!.mediaItem.listen(
        (mediaItem) {
          if (mediaItem == null) {
            return;
          }

          currentSong = Song(
            id: mediaItem.id,
            title: mediaItem.title,
            artist: mediaItem.artist ?? 'Unknown Artist',
            album: mediaItem.album ?? 'Unknown Album',
            filePath:
                mediaItem.extras?['filePath']
                        ?.toString() ??
                    '',
            duration:
                mediaItem.duration ??
                    Duration.zero,
            dateAdded: DateTime.now(),
            albumArt:
                mediaItem.extras?['albumArt']
                    ?.toString(),
          );

          currentDuration =
              mediaItem.duration;

          notifyListeners();
        },
      );
    }

    // Local fallback player.
    audioPlayer.playerStateStream.listen(
      (state) {
        // Only use the local player state when
        // there is no background audio handler.
        if (audioHandler != null) {
          return;
        }

        final playing = state.playing;

        if (isPlaying != playing) {
          isPlaying = playing;
          notifyListeners();
        }
      },
    );

    audioPlayer.positionStream.listen(
      (position) {
        if (audioHandler != null) {
          return;
        }

        currentPosition = position;
        notifyListeners();
      },
    );

    audioPlayer.durationStream.listen(
      (duration) {
        if (audioHandler != null) {
          return;
        }

        currentDuration = duration;
        notifyListeners();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // PLAY SONG
  // ---------------------------------------------------------------------------

  Future<void> playSong(Song song) async {
    currentSong = song;
    currentDuration = song.duration;

    notifyListeners();

    // Background audio handler.
    if (audioHandler != null) {
      try {
        final mediaItem = MediaItem(
          id: song.id,
          album: song.album,
          title: song.title,
          artist: song.artist,
          duration: song.duration,
          extras: {
            'filePath': song.filePath,
            'albumArt': song.albumArt,
          },
        );

        await audioHandler!.addQueueItem(
          mediaItem,
        );

        await audioHandler!.play();

        return;
      } catch (e) {
        debugPrint(
          'Error playing through AudioService: $e',
        );
      }
    }

    // Local fallback.
    try {
      if (currentSong?.id != song.id) {
        await audioPlayer.setAudioSource(
          AudioSource.uri(
            Uri.file(song.filePath),
          ),
        );
      }

      currentSong = song;

      await audioPlayer.play();

      isPlaying = true;

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Error playing song locally: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PLAY / PAUSE
  // ---------------------------------------------------------------------------

  Future<void> togglePlayPause() async {
    if (audioHandler != null) {
      final state =
          await audioHandler!.playbackState.first;

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

      isPlaying = false;
      currentPosition = Duration.zero;

      notifyListeners();

      return;
    }

    await audioPlayer.stop();

    isPlaying = false;
    currentSong = null;
    currentPosition = Duration.zero;
    currentDuration = null;

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // NEXT / PREVIOUS
  // ---------------------------------------------------------------------------

  Future<void> nextSong() async {
    if (audioHandler != null) {
      await audioHandler!.skipToNext();
      return;
    }

    if (_queue.isNotEmpty &&
        _queueIndex < _queue.length - 1) {
      _queueIndex++;

      await playSong(
        _queue[_queueIndex],
      );
    }
  }

  Future<void> previousSong() async {
    if (audioHandler != null) {
      await audioHandler!.skipToPrevious();
      return;
    }

    if (_queue.isNotEmpty &&
        _queueIndex > 0) {
      _queueIndex--;

      await playSong(
        _queue[_queueIndex],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SEEK
  // ---------------------------------------------------------------------------

  Future<void> seek(
    Duration position,
  ) async {
    if (audioHandler != null) {
      await audioHandler!.seek(position);

      currentPosition = position;
      notifyListeners();

      return;
    }

    await audioPlayer.seek(position);

    currentPosition = position;

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // VOLUME
  // ---------------------------------------------------------------------------

  Future<void> setVolume(double volume) async {
    final safeVolume =
        volume.clamp(0.0, 1.0);

    // If using our concrete handler, use its
    // volume functionality.
    if (audioHandler is AudioServiceHandler) {
      await (audioHandler as AudioServiceHandler)
          .setVolume(safeVolume);

      return;
    }

    await audioPlayer.setVolume(
      safeVolume,
    );

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // QUEUE
  // ---------------------------------------------------------------------------

  Future<void> setQueue(
    List<Song> songs, {
    int startIndex = 0,
  }) async {
    _queue = List<Song>.from(songs);

    if (_queue.isEmpty) {
      _queueIndex = 0;
      return;
    }

    _queueIndex = startIndex.clamp(
      0,
      _queue.length - 1,
    );

    if (audioHandler is AudioServiceHandler) {
      await (audioHandler as AudioServiceHandler)
          .setSongQueue(
        _queue,
        startIndex: _queueIndex,
      );

      return;
    }

    try {
      final sources = _queue.map(
        (song) {
          return AudioSource.uri(
            Uri.file(song.filePath),
          );
        },
      ).toList();

      await audioPlayer.setAudioSource(
        ConcatenatingAudioSource(
          children: sources,
        ),
        initialIndex: _queueIndex,
      );

      currentSong = _queue[_queueIndex];

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Error setting queue: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // STREAMS
  // ---------------------------------------------------------------------------

  Stream<Duration?> get durationStream {
    if (audioHandler != null) {
      return audioHandler!
          .playbackState
          .map(
            (_) => currentDuration,
          );
    }

    return audioPlayer.durationStream;
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _handlerPlaybackSubscription?.cancel();
    _handlerMediaItemSubscription?.cancel();

    audioPlayer.dispose();

    super.dispose();
  }
}
