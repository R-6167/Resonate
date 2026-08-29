import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();

  AudioPlayerHandler() {
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Broadcast playback events to clients
    _player.playbackEventStream.listen((event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        playing: playing,
        processingState: {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.connecting,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        position: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ));
    });
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setUrl(String url) async {
    await _player.setFilePath(url);
  }

  Future<void> setMediaItemWithExtras(MediaItem item, String path) async {
    mediaItem.add(item);
    await _player.setFilePath(path);
  }
}

// Background entry point used by audio_service when starting background isolates.
@pragma('vm:entry-point')
AudioHandler audioHandlerFactory() => AudioPlayerHandler();
