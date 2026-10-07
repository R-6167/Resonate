import '../../models/song.dart';
import '../models/media_type.dart';
import '../models/mode_media_item.dart';
import '../models/resonate_mode.dart';
import '../providers/mode_provider.dart';
import 'audiobook_coordinator.dart';

/// Host-side adapter for the Audiobook Mode coordinator.
///
/// Audiobook semantics apply only when Audiobook Mode is active and the
/// current item is classified as an audiobook. Canonical Library access is
/// never restricted by this bridge.
class AudiobookSessionBridge {
  final AudiobookCoordinator coordinator;
  String? _songId;

  AudiobookSessionBridge({AudiobookCoordinator? coordinator})
      : coordinator = coordinator ?? AudiobookCoordinator();

  bool get isActive => coordinator.isActive;

  bool _isAudiobook(ModeProvider? modes, Song? song) {
    if (modes == null ||
        song == null ||
        modes.mode != ResonateMode.audiobook ||
        song.filePath.trim().isEmpty) {
      return false;
    }
    final item = ModeMediaItem(
      id: song.id,
      filePath: song.filePath,
      title: song.title,
      album: song.album,
      artist: song.artist,
    );
    return modes.mediaTypeFor(item) == MediaType.audiobook;
  }

  void sync({
    required ModeProvider modes,
    required Song? song,
    required Duration position,
    required bool playing,
  }) {
    if (_isAudiobook(modes, song)) {
      final audiobookSong = song!;
      if (!coordinator.isActive || _songId != audiobookSong.id) {
        if (coordinator.isActive) {
          coordinator.exit(DateTime.now(), position: position);
        }
        _songId = audiobookSong.id;
        if (playing) {
          coordinator.start(
            DateTime.now(),
            resumePosition: position > Duration.zero ? position : null,
          );
        }
      } else if (playing && coordinator.isPaused) {
        coordinator.resume(DateTime.now(), position: position);
      } else if (!playing && !coordinator.isPaused) {
        coordinator.pause(DateTime.now(), position: position);
      }
      return;
    }

    if (coordinator.isActive || coordinator.isPaused) {
      coordinator.exit(DateTime.now(), position: position);
    }
    _songId = null;
  }

  void onSongStarted({
    required ModeProvider? modes,
    required Song song,
    Duration? resumePosition,
  }) {
    if (!_isAudiobook(modes, song)) {
      onStopped(resumePosition ?? Duration.zero);
      return;
    }
    if (coordinator.isActive || coordinator.isPaused) {
      coordinator.exit(DateTime.now(), position: resumePosition);
    }
    _songId = song.id;
    coordinator.start(DateTime.now(), resumePosition: resumePosition);
  }

  void onPaused(Duration position) {
    if (coordinator.isActive) {
      coordinator.pause(DateTime.now(), position: position);
    }
  }

  void onResumed(Duration position) {
    if (coordinator.isActive && coordinator.isPaused) {
      coordinator.resume(DateTime.now(), position: position);
    }
  }

  void onCompleted(Duration position) {
    if (coordinator.isActive) {
      coordinator.complete(DateTime.now(), position: position);
    }
    _songId = null;
  }

  void onStopped(Duration position) {
    if (coordinator.isActive || coordinator.isPaused) {
      coordinator.exit(DateTime.now(), position: position);
    }
    _songId = null;
  }
}
